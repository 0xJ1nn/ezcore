import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'core_session_backend.dart';
import 'supervisor_session.dart';

/// Thrown when the host process ended while (or before) a command ran. The
/// [classification] says whether the core crashed, hung, or exited.
class CoreSessionEndedException implements Exception {
  CoreSessionEndedException(this.classification, {this.stderrTail = ''});

  final ExitClassification classification;

  /// The last lines the host printed, for a diagnostic. May be empty.
  final String stderrTail;

  @override
  String toString() => switch (classification.outcome) {
    SessionOutcome.crashed =>
      'The core crashed (exit ${classification.exitCode}). '
          'ezCORE is fine; only this game session ended.',
    SessionOutcome.hung =>
      'The core stopped responding and was stopped. '
          'ezCORE is fine; only this game session ended.',
    SessionOutcome.clean => 'The core session ended.',
  };
}

/// Runs a core session in a separate `ezcore_core_host` process (P6,
/// ADR-015), speaking the protocol in
/// `runtime/host/ezcore_core_host_protocol.h`. A crash in the core kills that
/// process, never this one; the next command then fails with a
/// [CoreSessionEndedException] that says what happened.
///
/// One command is in flight at a time (the player already works this way),
/// and each one is bounded by [watchdog]: a host that stops answering is
/// killed and reported as hung, not crashed.
class ProcessSessionBackend implements CoreSessionBackend {
  ProcessSessionBackend({
    required this.hostPath,
    this.arguments = const [],
    this.environment,
    this.watchdog = const Duration(seconds: 10),
    this.openWatchdog = const Duration(seconds: 60),
  });

  final String hostPath;
  final List<String> arguments;
  final Map<String, String>? environment;

  /// Per-command limit once a session is open.
  final Duration watchdog;

  /// Limit for OPEN, which may load a large core and its content.
  final Duration openWatchdog;

  Process? _process;
  // Received bytes not yet consumed, kept as chunks so a 1 MB frame is
  // assembled with one copy instead of being re-copied on every chunk.
  final List<Uint8List> _rx = [];
  int _rxLen = 0;
  Completer<Uint8List>? _pending;
  Future<void> _queue = Future.value();
  final List<String> _stderr = [];
  Duration? _watchdogFired;

  /// How the host process ended, once it has.
  ExitClassification? lastExit;

  static const _opOpen = 1, _opFrame = 2, _opPause = 3, _opButton = 4;
  static const _opSave = 5, _opRestore = 6, _opCheats = 7, _opReset = 8;
  static const _opOptions = 9, _opSetOption = 10, _opClose = 11;
  static const _opAnalog = 12, _opMouseMove = 13, _opMouseBtn = 14;
  static const _opKey = 15, _opPointer = 16;

  Future<void> _ensureStarted() async {
    if (_process != null || lastExit != null) return;
    final p = await Process.start(
      hostPath,
      arguments,
      environment: environment,
    );
    _process = p;
    p.stdout.listen(_onBytes, onDone: () {});
    p.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          _stderr.add(line);
          if (_stderr.length > 64) _stderr.removeAt(0);
        });
    unawaited(
      p.exitCode.then((code) {
        lastExit = classifyExit(exitCode: code, watchdogAfter: _watchdogFired);
        final pending = _pending;
        _pending = null;
        pending?.completeError(_ended());
      }),
    );
  }

  CoreSessionEndedException _ended() => CoreSessionEndedException(
    lastExit ?? classifyExit(),
    stderrTail: _stderr.join('\n'),
  );

  void _onBytes(List<int> chunk) {
    final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
    _rx.add(bytes);
    _rxLen += bytes.length;
    final pending = _pending;
    if (pending == null || _rxLen < 4) return;
    final n = ByteData.sublistView(
      _take(4, consume: false),
    ).getUint32(0, Endian.little);
    if (_rxLen < 4 + n) return;
    _take(4);
    final body = _take(n);
    _pending = null;
    pending.complete(body);
  }

  /// Copies the first [n] buffered bytes into one list, removing them unless
  /// [consume] is false.
  Uint8List _take(int n, {bool consume = true}) {
    final out = Uint8List(n);
    var filled = 0, i = 0;
    while (filled < n) {
      final c = _rx[i];
      final want = n - filled;
      final m = c.length < want ? c.length : want;
      out.setRange(filled, filled + m, c);
      filled += m;
      if (consume) {
        if (m == c.length) {
          _rx.removeAt(i);
        } else {
          _rx[i] = Uint8List.sublistView(c, m);
        }
      } else {
        i++;
      }
    }
    if (consume) _rxLen -= n;
    return out;
  }

  /// Sends one request and returns the response body after the status byte.
  /// Commands are serialised; an EZH_ERROR answer becomes a [StateError].
  Future<_Reader> _call(_Writer req, {Duration? limit}) {
    final run = _queue.then((_) => _send(req, limit ?? watchdog));
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<_Reader> _send(_Writer req, Duration limit) async {
    if (lastExit != null) throw _ended();
    await _ensureStarted();
    final p = _process!;
    final body = req.bytes();
    final header = ByteData(4)..setUint32(0, body.length, Endian.little);
    final completer = Completer<Uint8List>();
    _pending = completer;
    // The host may have died while we were starting it (that await yields);
    // its exit handler then had no pending command to fail, so check here
    // rather than wait for the watchdog and misfile a crash as a hang.
    if (lastExit != null) {
      _pending = null;
      throw _ended();
    }
    try {
      p.stdin.add(header.buffer.asUint8List());
      p.stdin.add(body);
      await p.stdin.flush();
    } catch (_) {
      // The host is gone; its exit handler completes [completer].
    }
    final Uint8List resp;
    try {
      resp = await completer.future.timeout(limit);
    } on TimeoutException {
      _watchdogFired = limit;
      _pending = null;
      p.kill(ProcessSignal.sigkill);
      await p.exitCode;
      throw _ended();
    }
    final r = _Reader(resp);
    final status = r.u8();
    if (status != 0) {
      throw StateError(utf8.decode(resp.sublist(1), allowMalformed: true));
    }
    return r;
  }

  @override
  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
    Map<String, String> coreOptions = const {},
  }) async {
    final w = _Writer()
      ..u8(_opOpen)
      ..str(corePath)
      ..str(contentPath)
      ..str(systemDir)
      ..str(saveDir)
      ..u32(coreOptions.length);
    coreOptions.forEach(
      (k, v) => w
        ..str(k)
        ..str(v),
    );
    final r = await _call(w, limit: openWatchdog);
    final name = r.str();
    final width = r.u32(), height = r.u32();
    final fps = r.f64(), rate = r.f64();
    final rejected = [for (var i = r.u32(); i > 0; i--) r.str()];
    return {
      'name': name,
      'width': width,
      'height': height,
      'fps': fps,
      'sampleRate': rate,
      'rejectedOptions': rejected,
    };
  }

  @override
  Future<Map<String, dynamic>?> frame({int count = 1}) async {
    if (count < 1 || count > 8) throw RangeError.range(count, 1, 8);
    final r = await _call(
      _Writer()
        ..u8(_opFrame)
        ..u32(count),
    );
    if (r.u8() == 0) return null;
    final width = r.u32(), height = r.u32();
    return {
      'width': width,
      'height': height,
      'rgba': r.blob(),
      'pcm': r.blob(),
    };
  }

  @override
  Future<void> pause(bool value) => _call(
    _Writer()
      ..u8(_opPause)
      ..u8(value ? 1 : 0),
  );

  @override
  Future<void> button(int id, bool pressed, {int port = 0}) async {
    if (id < 0 || id > 15) throw RangeError.range(id, 0, 15);
    if (port < 0 || port > 3) throw RangeError.range(port, 0, 3, 'port');
    await _call(
      _Writer()
        ..u8(_opButton)
        ..u32(port)
        ..u32(id)
        ..u8(pressed ? 1 : 0),
    );
  }

  @override
  Future<void> analog(int port, int stick, int axis, int value) => _call(
    _Writer()
      ..u8(_opAnalog)
      ..u32(port)
      ..u32(stick)
      ..u32(axis)
      ..i32(value),
  );

  @override
  Future<void> mouseMove(int dx, int dy) => _call(
    _Writer()
      ..u8(_opMouseMove)
      ..i32(dx)
      ..i32(dy),
  );

  @override
  Future<void> mouseButton(int id, bool pressed) => _call(
    _Writer()
      ..u8(_opMouseBtn)
      ..u32(id)
      ..u8(pressed ? 1 : 0),
  );

  @override
  Future<void> key(
    int keycode,
    bool pressed, {
    int character = 0,
    int modifiers = 0,
  }) => _call(
    _Writer()
      ..u8(_opKey)
      ..u32(keycode)
      ..u8(pressed ? 1 : 0)
      ..u32(character)
      ..u32(modifiers),
  );

  @override
  Future<void> pointer(int x, int y, bool pressed) => _call(
    _Writer()
      ..u8(_opPointer)
      ..i32(x)
      ..i32(y)
      ..u8(pressed ? 1 : 0),
  );

  @override
  Future<Uint8List> save() async =>
      (await _call(_Writer()..u8(_opSave))).blob();

  @override
  Future<void> restore(Uint8List bytes) => _call(
    _Writer()
      ..u8(_opRestore)
      ..blob(bytes),
  );

  @override
  Future<List<int>> applyCheats(List<List<Object>> cheats) async {
    final w = _Writer()
      ..u8(_opCheats)
      ..u32(cheats.length);
    for (final c in cheats) {
      w
        ..u32(c[0] as int)
        ..u8((c[1] as bool) ? 1 : 0)
        ..str(c[2] as String);
    }
    final r = await _call(w);
    return [for (var i = r.u32(); i > 0; i--) r.u32()];
  }

  @override
  Future<void> reset() => _call(_Writer()..u8(_opReset));

  @override
  Future<List<Map<String, String>>> coreOptions() async {
    final r = await _call(_Writer()..u8(_opOptions));
    return [
      for (var i = r.u32(); i > 0; i--)
        {'key': r.str(), 'default': r.str(), 'value': r.str()},
    ];
  }

  @override
  Future<bool> setCoreOption(String key, String value) async {
    final r = await _call(
      _Writer()
        ..u8(_opSetOption)
        ..str(key)
        ..str(value),
    );
    return r.u8() == 1;
  }

  /// Ends the session. Safe after a crash, and safe to call twice.
  @override
  Future<void> close() async {
    final p = _process;
    if (p == null) return;
    if (lastExit == null) {
      try {
        await _call(_Writer()..u8(_opClose), limit: const Duration(seconds: 5));
      } catch (_) {
        // A host that cannot close cleanly is stopped below.
      }
    }
    try {
      await p.stdin.close();
    } catch (_) {}
    final code = await p.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return p.exitCode;
      },
    );
    lastExit ??= classifyExit(exitCode: code, watchdogAfter: _watchdogFired);
    _process = null;
  }
}

class _Writer {
  final _b = BytesBuilder(copy: false);

  void u8(int v) => _b.addByte(v);

  void u32(int v) => _b.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );

  void i32(int v) => _b.add(
    (ByteData(4)..setInt32(0, v, Endian.little)).buffer.asUint8List(),
  );

  void str(String s) {
    final bytes = utf8.encode(s);
    u32(bytes.length);
    _b.add(bytes);
  }

  void blob(Uint8List bytes) {
    u32(bytes.length);
    _b.add(bytes);
  }

  Uint8List bytes() => _b.toBytes();
}

class _Reader {
  _Reader(this._bytes) : _data = ByteData.sublistView(_bytes);

  final Uint8List _bytes;
  final ByteData _data;
  int _at = 0;

  int u8() => _data.getUint8(_at++);

  int u32() {
    final v = _data.getUint32(_at, Endian.little);
    _at += 4;
    return v;
  }

  double f64() {
    final v = _data.getFloat64(_at, Endian.little);
    _at += 8;
    return v;
  }

  String str() {
    final n = u32();
    final s = utf8.decode(Uint8List.sublistView(_bytes, _at, _at + n));
    _at += n;
    return s;
  }

  Uint8List blob() {
    final n = u32();
    final out = Uint8List.sublistView(_bytes, _at, _at + n);
    _at += n;
    return out;
  }
}
