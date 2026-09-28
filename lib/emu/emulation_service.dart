import 'dart:ffi';
import 'dart:typed_data';

import '../runtime/ezcore_runtime.dart';

class EmulationException implements Exception {
  const EmulationException(this.message);
  final String message;
  @override
  String toString() => 'EmulationException: $message';
}

/// Single-owner session adapter over the existing native ABI.
///
/// Call only from one execution context. This adapter does not schedule frames,
/// play PCM, resolve artifacts, or persist bytes: those belong to the host.
/// Callers must verify a core's manifest pin before passing its path here.
class EmulationService {
  EmulationService({required this.runtime});
  final EzCoreRuntime runtime;
  Pointer<Void>? _session;

  bool get isRunning => _session != null;
  Pointer<Void> get _active =>
      _session ?? (throw StateError('No active emulation session'));

  String get coreName => runtime.coreName(_active);
  ({int w, int h, double fps}) get geometry => runtime.geometry(_active);
  double get sampleRate => runtime.sampleRate(_active);
  int get frameWidth => geometry.w;
  int get frameHeight => geometry.h;
  int get audioPending => runtime.audioPending(_active);

  Future<void> start({
    required String corePath,
    required String romPath,
    required Uint8List rom,
  }) async {
    if (isRunning) {
      throw StateError('Close the current session before starting');
    }
    Pointer<Void>? candidate;
    try {
      candidate = runtime.loadSession(corePath);
      if (!runtime.init(candidate)) {
        throw const EmulationException('Core initialization failed');
      }
      if (!runtime.loadGame(candidate, romPath, rom)) {
        throw const EmulationException('Core rejected the content');
      }
      _session = candidate;
    } catch (error) {
      if (candidate != null) runtime.unload(candidate);
      if (error is EmulationException) rethrow;
      throw EmulationException(error.toString());
    }
  }

  void runFrame() => runtime.runFrame(_active);
  Uint8List? frameBytes() => runtime.frameBytes(_active);
  void setButton(int port, int button, bool pressed) =>
      runtime.setButton(_active, port, button, pressed);

  /// Applies [cheats] to the live session (reset-first, mirroring
  /// RetroArch). Each entry is `(index, enabled, code)`. Returns the
  /// indices the runtime could not dispatch to a core hook.
  List<int> applyCheats(List<({int index, bool enabled, String code})> cheats) {
    final session = _active;
    runtime.cheatReset(session);
    final notDispatched = <int>[];
    for (final c in cheats) {
      if (c.code.trim().isEmpty) continue;
      if (!runtime.cheatSet(session, c.index, c.enabled, c.code)) {
        notDispatched.add(c.index);
      }
    }
    return notDispatched;
  }

  void reset() => runtime.reset(_active);
  Uint8List? saveState() => runtime.saveState(_active);
  bool loadState(Uint8List bytes) => runtime.loadState(_active, bytes);

  /// Adds only produced stereo signed-16 PCM bytes, never unused capacity.
  int drainAudio(int frames, BytesBuilder output) {
    final session = _active;
    if (frames < 0 || frames > 65536) {
      throw RangeError.range(frames, 0, 65536, 'frames');
    }
    if (frames == 0) return 0;
    final bytes = Uint8List(frames * 4);
    final count = runtime.drainAudio(session, frames, bytes.buffer);
    output.add(Uint8List.sublistView(bytes, 0, count * 4));
    return count;
  }

  void close() {
    final session = _session;
    _session = null;
    if (session != null) runtime.unload(session);
  }
}
