// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import '../models/cheat.dart';
import '../state/save_sync.dart';
import 'core_session_backend.dart';
import 'emulation_worker.dart';
import 'pcm_output.dart';
import 'video_texture.dart';

/// Frame scheduling/presentation only; native sessions belong to the worker.
/// One outstanding frame bounds memory even when rendering is slower than emulation.
class PlayerController extends ChangeNotifier {
  PlayerController({PcmOutput? audio, VideoTextureController? video})
      : audio = audio ?? createPlatformPcm(),
        video = video ?? VideoTextureController();
  final PcmOutput audio;

  /// Android presents frames into a Flutter surface; other targets keep the
  /// decoded-image path until the native loop takes over.
  final VideoTextureController video;
  final FrameStats frameStats = FrameStats();
  bool get usingTexture => video.active;

  /// Runs the core session. In-process by default; [useBackend] swaps in a
  /// separate-process backend (P6) before [open].
  CoreSessionBackend worker = EmulationWorker();

  /// Selects what runs the session. Only valid before [open].
  void useBackend(CoreSessionBackend backend) {
    if (running) throw StateError('Cannot change backend of a live session');
    worker = backend;
  }

  ui.Image? frame;
  String? error;
  String? audioError;
  bool paused = false, fastForward = false, running = false;

  /// False when the core has no save states at all (the LCD-handheld core
  /// reports a zero serialize size). The pause menu then hides the snapshot
  /// affordance instead of offering a button that can only fail.
  bool canSaveStates = true;

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
  DateTime? _lastFrameAt;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
    Map<String, String> coreOptions = const {},
  }) async {
    final info = await worker.open(
      runtimeRef: runtimeRef,
      corePath: corePath,
      contentPath: contentPath,
      systemDir: systemDir,
      saveDir: saveDir,
      coreOptions: coreOptions,
    );
    if (_closed) {
      await worker.close();
      return;
    }
    _fps = (info['fps'] as num).toDouble();
    if (!_fps.isFinite || _fps <= 0) _fps = 60;
    _rate = (info['sampleRate'] as num).toDouble();
    canSaveStates = info['canSave'] as bool? ?? true;
    await _attachVideo((info['width'] as num?)?.toInt() ?? 0,
        (info['height'] as num?)?.toInt() ?? 0);
    await _startAudio();
    running = true;
    // Frame times start at session start, so the first presented frame is
    // measured like every other one and stats keep pace with presentations.
    _lastFrameAt = DateTime.now();
    _notify();
    _schedule(Duration.zero);
  }

  /// Creates the Android surface and hands its native window to the session.
  /// A failure leaves the decoded-image path in place; the player never stops
  /// showing frames because a texture could not be registered.
  Future<void> _attachVideo(int width, int height) async {
    if (width <= 0 || height <= 0) return;
    await video.create(width, height);
    final window = video.window;
    if (window == null || !await worker.attachVideo(window, width, height)) {
      await video.release();
      return;
    }
    // The stage still needs a frame object for layout. A one-pixel stand-in
    // keeps that path intact; the visible picture is the surface itself.
    final placeholder = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList(const [0, 0, 0, 255]),
      1,
      1,
      ui.PixelFormat.rgba8888,
      placeholder.complete,
    );
    if (!_closed) frame = await placeholder.future;
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
        final now = DateTime.now();
        final last = _lastFrameAt;
        if (last != null) frameStats.sample(now.difference(last));
        _lastFrameAt = now;

        if (usingTexture && packet['presented'] == true) {
          // The runtime wrote the frame into the surface. Flutter only needs a
          // nudge to composite it; no pixel copy crosses into Dart.
          await video.markFrame();
          if (frameStats.count > 0 && frameStats.count % 120 == 0) {
            debugPrint('ezcore/video frame-time: $frameStats');
          }
          _notify();
        } else {
          final data = packet['rgba'] as Uint8List?;
          if (data != null) {
            final completer = Completer<ui.Image>();
            ui.decodeImageFromPixels(
              data,
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
          }
        }
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
      _lastFrameAt = null;
    } else {
      await _startAudio();
      _lastFrameAt = DateTime.now();
      _schedule(Duration.zero);
    }
    _notify();
  }

  /// Sends a RetroPad transition for controller [port] (0-3, port 0 is
  /// player one). Defaults to 0 so the on-screen pad and keyboard are
  /// unchanged; a second gamepad routes through `port: 1`.
  Future<void> button(int id, bool pressed, {int port = 0}) async {
    if (running && !paused && !_closed) {
      await worker.button(id, pressed, port: port);
    }
  }

  bool get _live => running && !paused && !_closed;

  /// Analog stick axis for [port]: [stick] 0 left / 1 right, [axis] 0 x / 1 y.
  Future<void> analog(int port, int stick, int axis, int value) async {
    if (_live) await worker.analog(port, stick, axis, value);
  }

  Future<void> mouseMove(int dx, int dy) async {
    if (_live && (dx != 0 || dy != 0)) await worker.mouseMove(dx, dy);
  }

  Future<void> mouseButton(int id, bool pressed) async {
    if (_live) await worker.mouseButton(id, pressed);
  }

  Future<void> key(
    int keycode,
    bool pressed, {
    int character = 0,
    int modifiers = 0,
  }) async {
    if (_live) {
      await worker.key(
        keycode,
        pressed,
        character: character,
        modifiers: modifiers,
      );
    }
  }

  Future<void> pointer(int x, int y, bool pressed) async {
    if (_live) await worker.pointer(x, y, pressed);
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
      await video.release();
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
