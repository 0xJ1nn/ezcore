import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../models/cheat.dart';
import '../state/save_sync.dart';
import 'emulation_worker.dart';
import 'pcm_output.dart';

/// Frame scheduling/presentation only; native sessions belong to the worker.
/// One outstanding frame bounds memory even when rendering is slower than emulation.
class PlayerController extends ChangeNotifier {
  PlayerController({PcmOutput? audio})
      : audio = audio ?? createPlatformPcm();
  final PcmOutput audio;
  final EmulationWorker worker = EmulationWorker();
  ui.Image? frame;
  String? error;
  String? audioError;
  bool paused = false, fastForward = false, running = false;

  /// Session-start audio/image pacing prefs (set by the player before `open`
  /// returns frames): [muted] drops PCM, [volume] scales s16 samples 0-100,
  /// [ffFrames] is the frames-per-tick fast-forward speed (worker allows 1-8).
  bool muted = false;
  int volume = 80;
  int ffFrames = 4;
  bool _closed = false, _disposed = false, _audioReady = false;
  double _fps = 60, _rate = 44100;
  Timer? _timer;
  Future<void>? _inFlight;
  Future<void>? _closeFuture;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
  }) async {
    final info = await worker.open(
      runtimeRef: runtimeRef,
      corePath: corePath,
      contentPath: contentPath,
      systemDir: systemDir,
      saveDir: saveDir,
    );
    if (_closed) {
      await worker.close();
      return;
    }
    _fps = (info['fps'] as num).toDouble();
    if (!_fps.isFinite || _fps <= 0) _fps = 60;
    _rate = (info['sampleRate'] as num).toDouble();
    await _startAudio();
    running = true;
    _notify();
    _schedule(Duration.zero);
  }

  Future<void> _startAudio() async {
    try {
      await audio.start(_rate);
      _audioReady = true;
      audioError = null;
    } catch (e) {
      audioError = 'Audio unavailable: $e';
      _audioReady = false;
    }
  }

  void _schedule(Duration delay) {
    if (_closed || paused || !running) return;
    _timer = Timer(delay, () {
      _inFlight = _tick();
    });
  }

  Future<void> _tick() async {
    final clock = Stopwatch()..start();
    try {
      final packet = await worker.frame(count: fastForward ? ffFrames : 1);
      if (packet != null && !_closed && !paused) {
        final completer = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          packet['rgba'] as Uint8List,
          packet['width'] as int,
          packet['height'] as int,
          ui.PixelFormat.rgba8888,
          completer.complete,
        );
        final next = await completer.future;
        if (_closed || paused) {
          next.dispose();
          return;
        }
        final previous = frame;
        frame = next;
        _notify();
        previous?.dispose();
        if (_audioReady && !muted) {
          try {
            await audio.write(_applyGain(packet['pcm'] as Uint8List));
          } catch (e) {
            audioError = 'Audio unavailable: $e';
            _audioReady = false;
            _notify();
          }
        }
      }
    } catch (e) {
      error = e.toString();
      running = false;
      _notify();
    } finally {
      final remaining = (1000000 / _fps).round() - clock.elapsedMicroseconds;
      _schedule(Duration(microseconds: remaining.clamp(0, 1000000)));
    }
  }

  Future<void> setPaused(bool value) async {
    if (_closed || !running) return;
    paused = value;
    _timer?.cancel();
    await _inFlight;
    await worker.pause(value);
    if (value) {
      if (_audioReady) await audio.stop();
      _audioReady = false;
    } else {
      await _startAudio();
      _schedule(Duration.zero);
    }
    _notify();
  }

  Future<void> button(int id, bool pressed) async {
    if (running && !paused && !_closed) await worker.button(id, pressed);
  }

  /// Applies [entries] to the live session (reset-first). Returns the
  /// indices the runtime could not dispatch to a core hook. No-op when no
  /// session is running.
  Future<List<int>> applyCheats(List<CheatEntry> entries) async {
    if (!running || _closed) return [];
    return worker.applyCheats([
      for (final e in entries) [e.index, e.enabled, joinCheatCode(e.code)],
    ]);
  }

  /// Scales stereo s16 [pcm] by [volume] (0-100). 100+ passes through.
  Uint8List _applyGain(Uint8List pcm) {
    final v = volume.clamp(0, 100);
    if (v >= 100 || pcm.isEmpty) return pcm;
    if (v <= 0) return Uint8List(pcm.length);
    final out = Uint8List(pcm.length);
    final src = ByteData.sublistView(pcm);
    final dst = ByteData.sublistView(out);
    final g = v / 100;
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      final s = src.getInt16(i, Endian.little);
      dst.setInt16(i, (s * g).round().clamp(-32768, 32767), Endian.little);
    }
    return out;
  }

  Future<void> save(SaveSyncProvider saves, String game, String slot) async =>
      saves.upload(game, slot, await worker.save());
  Future<void> restore(SaveSyncProvider saves, String game, String slot) async {
    final bytes = await saves.download(game, slot);
    if (bytes == null) throw StateError('No state in this slot');
    await worker.restore(bytes);
  }

  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _closed = true;
    running = false;
    _timer?.cancel();
    await _inFlight;
    try {
      await worker.close();
    } finally {
      if (_audioReady) await audio.stop();
      _audioReady = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(close());
    frame?.dispose();
    frame = null;
    super.dispose();
  }
}
