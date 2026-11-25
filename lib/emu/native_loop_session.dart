// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// Dart-side handle for the runtime-owned run thread. The runtime advances the
// core on its own thread; this class starts and stops that thread, writes input
// into the atomics it reads before each frame, and samples its counters at a
// low rate for the display. None of the symbols here are required by older
// runtimes: when they are absent the caller keeps the original frame path.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';

/// The setting that keeps the per-frame timer path. It has no user interface;
/// it exists so one release can opt out of the new path if a device misbehaves.
const String kLegacyFrameLoopSetting = 'player.frameLoop';
const String _legacyTimerValue = 'timer';

/// Targets this player can present a run-loop frame on.
const Set<String> kLoopTargets = {'ios', 'android', 'macos', 'linux', 'windows'};

/// The target whose platform channel owns video presentation.
String get currentLoopTarget => Platform.isIOS
    ? 'ios'
    : Platform.isAndroid
        ? 'android'
        : Platform.isMacOS
            ? 'macos'
            : Platform.isWindows
                ? 'windows'
                : 'linux';

/// A snapshot of the run thread's counters. Values are sampled, not live.
class NativeLoopStats {
  const NativeLoopStats({
    this.framesRun = 0,
    this.droppedFrames = 0,
    this.audioUnderruns = 0,
    this.controlPending = 0,
    this.frameMeanMs = 0,
    this.frameP95Ms = 0,
  });

  final int framesRun;
  final int droppedFrames;
  final int audioUnderruns;
  final int controlPending;
  final double frameMeanMs;
  final double frameP95Ms;

  @override
  String toString() =>
      'frames=$framesRun dropped=$droppedFrames underruns=$audioUnderruns '
      'mean=${frameMeanMs.toStringAsFixed(2)}ms '
      'p95=${frameP95Ms.toStringAsFixed(2)}ms';
}

/// The small part of the native loop the player talks to. Implemented by the
/// optional runtime FFI surface and by fakes in tests.
abstract interface class NativeLoopBinding {
  bool get symbolsPresent;
  bool get videoBridgePresent;
  int start(int sessionAddress, {int fps = 60});
  void stop(int loop);
  void setButton(int loop, int port, int id, bool pressed);
  void clearButtons(int loop, int port);
  void setAnalog(int loop, int port, int stick, int axis, int value);
  NativeLoopStats? stats(int loop);
  bool pause(int loop, bool paused);
  bool fastForward(int loop, int factor);
}

/// Whether [binding] can drive a visible session on [target]. Both parts must
/// be present: the loop alone has no way to show its frames, and a texture
/// bridge alone has nothing producing them.
bool nativeLoopReady(NativeLoopBinding binding, [String? target]) =>
    kLoopTargets.contains(target ?? currentLoopTarget) &&
    binding.symbolsPresent &&
    binding.videoBridgePresent;

/// The runtime has no run loop available for this session.
class NativeLoopUnavailable implements Exception {
  const NativeLoopUnavailable();

  @override
  String toString() => 'NativeLoopUnavailable: the runtime has no run loop';
}

/// Owns one runtime loop for one loaded session.
class NativeLoopSession {
  NativeLoopSession({
    required this.binding,
    required this.sessionAddress,
    this.fps = 60,
    this.statsInterval = const Duration(milliseconds: 500),
  }) : _stats = StreamController<NativeLoopStats>.broadcast();

  final NativeLoopBinding binding;
  final int sessionAddress;
  final double fps;
  final Duration statsInterval;
  final StreamController<NativeLoopStats> _stats;
  StreamSubscription<void>? _sampler;
  int? _loop;
  NativeLoopStats? lastStats;

  bool get supported => nativeLoopReady(binding);
  bool get started => _loop != null;

  /// Two samples per second by default: enough for a display readout without
  /// turning the HUD into a per-frame caller.
  Stream<NativeLoopStats> get statsStream => _stats.stream;

  /// Throws when the loaded runtime was built without the loop or its video
  /// bridge. The caller then keeps the original path.
  void start() {
    if (_loop != null || !supported) throw const NativeLoopUnavailable();
    final loop = binding.start(sessionAddress, fps: fps.round());
    if (loop == 0) throw const NativeLoopUnavailable();
    _loop = loop;
    _sampler = Stream.periodic(statsInterval).listen((_) {
      final value = binding.stats(loop);
      if (value == null) return;
      lastStats = value;
      if (!_stats.isClosed) _stats.add(value);
    });
  }

  void stop() {
    final loop = _loop;
    _loop = null;
    _sampler?.cancel();
    _sampler = null;
    if (loop != null) binding.stop(loop);
  }

  void dispose() {
    stop();
    _stats.close();
  }

  /// Writes the runtime's button atomic. No frame round trip is involved.
  void setButton(int port, int id, bool pressed) {
    final loop = _loop;
    if (loop != null) binding.setButton(loop, port, id, pressed);
  }

  void clearButtons(int port) {
    final loop = _loop;
    if (loop != null) binding.clearButtons(loop, port);
  }

  void setAnalog(int port, int stick, int axis, int value) {
    final loop = _loop;
    if (loop != null) binding.setAnalog(loop, port, stick, axis, value);
  }

  bool pause(bool paused) {
    final loop = _loop;
    return loop == null || binding.pause(loop, paused);
  }

  bool fastForward(int factor) {
    final loop = _loop;
    return loop == null || binding.fastForward(loop, factor);
  }
}

/// Creates the default session only when the loaded runtime can actually run
/// and present a loop. Returns null otherwise so the player keeps its timer.
typedef NativeLoopProbe =
    NativeLoopSession? Function({
  required Map<String, String?> runtimeRef,
  required int sessionAddress,
  required double fps,
});

NativeLoopSession? probeNativeLoop({
  required Map<String, String?> runtimeRef,
  required int sessionAddress,
  required double fps,
}) {
  if (sessionAddress == 0) return null;
  final binding = FfiNativeLoopBinding.fromRuntimeRef(runtimeRef);
  if (!nativeLoopReady(binding)) return null;
  return NativeLoopSession(
    binding: binding,
    sessionAddress: sessionAddress,
    fps: fps > 0 ? fps : 60,
  );
}

/// A persisted value that keeps the original per-frame timer path for one
/// release. There is no user interface for it.
bool legacyFrameLoopRequested(Map<String, dynamic> settings) =>
    settings[kLegacyFrameLoopSetting] == _legacyTimerValue;

// --- optional native ABI -------------------------------------------------
// Kept in step with the loop statistics layout published by the runtime:
// five 64-bit counters, six doubles, a size_t count and a pointer.

final class _LoopConfig extends Struct {
  @Uint32()
  external int targetFps;
  @Uint32()
  external int buckets;
  @Double()
  external double maxMs;
}

final class _LoopStats extends Struct {
  @Uint64()
  external int framesRun;
  @Uint64()
  external int droppedFrames;
  @Uint64()
  external int controlApplied;
  @Uint64()
  external int controlPending;
  @Uint64()
  external int audioUnderruns;
  @Double()
  external double lastMs;
  @Double()
  external double meanMs;
  @Double()
  external double p50Ms;
  @Double()
  external double p95Ms;
  @Double()
  external double p99Ms;
  @Double()
  external double maxMs;
  @IntPtr()
  external int histogramLen;
  external Pointer<Uint32> histogram;
}

typedef _StartNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<_LoopConfig>,
  Pointer<Uint8>,
  IntPtr,
);
typedef _StartDart = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<_LoopConfig>,
  Pointer<Uint8>,
  int,
);
typedef _VoidNative = Void Function(Pointer<Void>);
typedef _VoidDart = void Function(Pointer<Void>);
typedef _ButtonNative = Void Function(Pointer<Void>, Uint32, Uint32, Bool);
typedef _ButtonDart = void Function(Pointer<Void>, int, int, bool);
typedef _ClearNative = Void Function(Pointer<Void>, Uint32);
typedef _ClearDart = void Function(Pointer<Void>, int);
typedef _AnalogNative = Void Function(
  Pointer<Void>,
  Uint32,
  Uint32,
  Uint32,
  Int16,
);
typedef _AnalogDart = void Function(
  Pointer<Void>,
  int,
  int,
  int,
  int,
);
typedef _ControlNative = Uint64 Function(Pointer<Void>, Bool);
typedef _ControlDart = int Function(Pointer<Void>, bool);
typedef _SpeedNative = Uint64 Function(Pointer<Void>, Uint32);
typedef _SpeedDart = int Function(Pointer<Void>, int);
typedef _WaitNative = Bool Function(Pointer<Void>, Uint64, Uint32, Pointer<Bool>);
typedef _WaitDart = bool Function(Pointer<Void>, int, int, Pointer<Bool>);
typedef _StatsNative = Bool Function(Pointer<Void>, Pointer<_LoopStats>);
typedef _StatsDart = bool Function(Pointer<Void>, Pointer<_LoopStats>);

/// FFI binding over an optional runtime extension. A runtime built before the
/// run loop simply reports [symbolsPresent] as false.
class FfiNativeLoopBinding implements NativeLoopBinding {
  FfiNativeLoopBinding(DynamicLibrary library) {
    _bind(library);
  }

  factory FfiNativeLoopBinding.fromRuntimeRef(Map<String, String?> ref) {
    if (ref['kind'] == 'process') {
      return FfiNativeLoopBinding(DynamicLibrary.process());
    }
    final path = ref['path'];
    if (path == null || path.isEmpty) {
      return FfiNativeLoopBinding(DynamicLibrary.process());
    }
    return FfiNativeLoopBinding(DynamicLibrary.open(path));
  }

  _StartDart? _start;
  _VoidDart? _stop;
  _ButtonDart? _button;
  _ClearDart? _clear;
  _AnalogDart? _analog;
  _ControlDart? _pause;
  _SpeedDart? _speed;
  _WaitDart? _wait;
  _StatsDart? _statsFn;
  bool _video = false;

  void _bind(DynamicLibrary lib) {
    try {
      _start = lib
          .lookup<NativeFunction<_StartNative>>('ezcore_loop_start')
          .asFunction<_StartDart>();
      _stop = lib
          .lookup<NativeFunction<_VoidNative>>('ezcore_loop_stop')
          .asFunction<_VoidDart>();
      _button = lib
          .lookup<NativeFunction<_ButtonNative>>('ezcore_loop_set_button')
          .asFunction<_ButtonDart>();
      _clear = lib
          .lookup<NativeFunction<_ClearNative>>('ezcore_loop_clear_buttons')
          .asFunction<_ClearDart>();
      _analog = lib
          .lookup<NativeFunction<_AnalogNative>>('ezcore_loop_set_analog')
          .asFunction<_AnalogDart>();
      _pause = lib
          .lookup<NativeFunction<_ControlNative>>('ezcore_loop_control_pause')
          .asFunction<_ControlDart>();
      _speed = lib
          .lookup<NativeFunction<_SpeedNative>>('ezcore_loop_control_fast_forward')
          .asFunction<_SpeedDart>();
      _wait = lib
          .lookup<NativeFunction<_WaitNative>>('ezcore_loop_control_wait')
          .asFunction<_WaitDart>();
      _statsFn = lib
          .lookup<NativeFunction<_StatsNative>>('ezcore_loop_stats')
          .asFunction<_StatsDart>();
    } on Object {
      _start = null;
      return;
    }
    // A texture bridge is required before the run loop can own presentation.
    // Both published native bridges count; the remaining platform bridge is
    // installed by its runner and is therefore absent here.
    for (final name in const [
      'ezcore_video_attach',
      'ezcore_video_texture_publish_session',
    ]) {
      try {
        lib.lookup<NativeFunction<Bool Function(Pointer<Void>)>>(name);
        _video = true;
        break;
      } on Object {
        // Try the other bridge.
      }
    }
  }

  @override
  bool get symbolsPresent => _start != null && _stop != null && _statsFn != null;

  @override
  bool get videoBridgePresent => _video;

  @override
  int start(int sessionAddress, {int fps = 60}) {
    final start = _start;
    if (start == null || sessionAddress == 0) return 0;
    final config = _alloc(sizeOf<_LoopConfig>()).cast<_LoopConfig>();
    final error = _alloc(256).cast<Uint8>();
    try {
      config.ref
        ..targetFps = fps < 1 ? 60 : fps.round()
        ..buckets = 0
        ..maxMs = 0;
      return start(
        Pointer<Void>.fromAddress(sessionAddress),
        config,
        error,
        256,
      ).address;
    } finally {
      _free(config.cast());
      _free(error.cast());
    }
  }

  @override
  void stop(int loop) => _stop?.call(Pointer<Void>.fromAddress(loop));

  @override
  void setButton(int loop, int port, int id, bool pressed) => _button?.call(
        Pointer<Void>.fromAddress(loop),
        port,
        id,
        pressed,
      );

  @override
  void clearButtons(int loop, int port) =>
      _clear?.call(Pointer<Void>.fromAddress(loop), port);

  @override
  void setAnalog(int loop, int port, int stick, int axis, int value) =>
      _analog?.call(
        Pointer<Void>.fromAddress(loop),
        port,
        stick,
        axis,
        value.clamp(-32768, 32767),
      );

  @override
  NativeLoopStats? stats(int loop) {
    final read = _statsFn;
    if (read == null) return null;
    final value = _alloc(sizeOf<_LoopStats>()).cast<_LoopStats>();
    try {
      if (!read(Pointer<Void>.fromAddress(loop), value)) return null;
      return NativeLoopStats(
        framesRun: value.ref.framesRun,
        droppedFrames: value.ref.droppedFrames,
        audioUnderruns: value.ref.audioUnderruns,
        controlPending: value.ref.controlPending,
        frameMeanMs: value.ref.meanMs,
        frameP95Ms: value.ref.p95Ms,
      );
    } finally {
      _free(value.cast());
    }
  }

  @override
  bool pause(int loop, bool paused) {
    final enqueue = _pause;
    final wait = _wait;
    if (enqueue == null || wait == null) return false;
    final ptr = Pointer<Void>.fromAddress(loop);
    final token = enqueue(ptr, paused);
    if (token == 0) return false;
    final result = _alloc(sizeOf<Bool>()).cast<Bool>();
    try {
      return wait(ptr, token, 50, result) && result.value;
    } finally {
      _free(result.cast());
    }
  }

  @override
  bool fastForward(int loop, int factor) {
    final enqueue = _speed;
    final wait = _wait;
    if (enqueue == null || wait == null) return false;
    final ptr = Pointer<Void>.fromAddress(loop);
    final token = enqueue(ptr, factor < 1 ? 1 : factor);
    if (token == 0) return false;
    final result = _alloc(sizeOf<Bool>()).cast<Bool>();
    try {
      return wait(ptr, token, 50, result) && result.value;
    } finally {
      _free(result.cast());
    }
  }
}

final _libcMalloc = DynamicLibrary.process()
    .lookupFunction<Pointer<Void> Function(IntPtr), Pointer<Void> Function(int)>(
      'malloc',
    );
final _libcFree = DynamicLibrary.process()
    .lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>(
      'free',
    );

Pointer<Void> _alloc(int bytes) {
  final ptr = _libcMalloc(bytes);
  for (var i = 0; i < bytes; i++) {
    ptr.cast<Uint8>()[i] = 0;
  }
  return ptr;
}

void _free(Pointer<Void> ptr) => _libcFree(ptr);
