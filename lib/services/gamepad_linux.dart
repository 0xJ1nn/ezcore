import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

/// Linux physical gamepads over evdev (`/dev/input/event*`).
///
/// No plugins: readable event nodes are decoded directly (`input_event`
/// structs: buttons + dpad keys + absolute sticks) and emitted as
/// canonical vocab transitions (see lib/services/gamepad.dart).
///
/// Adoption is silent and safe: keyboard/mouse nodes are read but their
/// EV_KEY numbers don't intersect the gamepad tables, so they emit
/// nothing; the connection announces only on the first real gamepad
/// event. Nodes without read permission are skipped. Stick deflection
/// normalizes against the axis's true device range (from EVIOCGABS) and
/// only when both extremes have been observed, using a dead band: a
/// reading above 75% of the range is the positive direction, below 25%
/// the negative one, and anything between reports no direction. When
/// the device range is unknown the range is widened from observed
/// samples instead, and stays inactive until the axis has actually
/// moved.
///
/// Pointer motion is decoded but kept off the joypad path: EV_REL
/// (REL_X/REL_Y/REL_WHEEL) is forwarded to the optional [onPointer]
/// callback as raw axis deltas, never as a button and never as a
/// connection announcement (a mouse node streams EV_REL continuously
/// and would otherwise present itself as a gamepad).
class LinuxEvdevPads {
  LinuxEvdevPads();

  bool _running = false;
  Timer? _rescan;
  final _devices = <String, _EvdevDevice>{};
  final _announced = <String>{};

  static const evKey = 1;
  static const evRel = 2;
  static const evAbs = 3;

  // Linux input-event-codes.h button numbers.
  static const keyCodes = <int, String>{
    304: 'a', // BTN_SOUTH
    305: 'b', // BTN_EAST
    307: 'x', // BTN_NORTH
    308: 'y', // BTN_WEST
    310: 'lb', // BTN_TL
    311: 'rb', // BTN_TR
    312: 'lt', // BTN_TL2
    313: 'rt', // BTN_TR2
    314: 'select', // BTN_SELECT
    315: 'start', // BTN_START
    317: 'l3', // BTN_THUMBL
    318: 'r3', // BTN_THUMBR
    544: 'up', // BTN_DPAD_UP
    545: 'down', // BTN_DPAD_DOWN
    546: 'left', // BTN_DPAD_LEFT
    547: 'right', // BTN_DPAD_RIGHT
  };

  static const absAxes = <int>{0, 1, 3, 4}; // ABS_X/Y/RX/RY

  // Linux input-event-codes.h relative-axis numbers.
  static const relCodes = <int, String>{
    0: 'rel_x', // REL_X
    1: 'rel_y', // REL_Y
    8: 'rel_wheel', // REL_WHEEL
  };

  /// Pure helper: decodes one 24-byte input_event into (type, code, value).
  static (int, int, int)? parseEvent(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < 24) return null;
    final data = ByteData.sublistView(bytes, offset, offset + 24);
    final type = data.getUint16(16, Endian.host);
    final code = data.getUint16(18, Endian.host);
    final value = data.getInt32(20, Endian.host);
    return (type, code, value);
  }

  /// EVIOCGABS for an axis: `_IOC(READ, 'E', 0x40 + code, absinfo)`.
  ///
  /// 2 << 30 (read) | 24 << 16 (sizeof(struct input_absinfo)) |
  /// 0x45 << 8 ('E') | 0x40 (ABS_X). Correct for the asm-generic ioctl
  /// encoding used by x86/x86-64/arm/arm64/riscv — every Flutter desktop
  /// target this build ships.
  static int evioCgabs(int code) => 0x80184540 + code;

  /// `struct input_absinfo` is six __s32: value, minimum, maximum, fuzz,
  /// flat, resolution. 24 bytes; we read `minimum` and `maximum`.
  static const _absinfoBytes = 24;
  static const _absinfoMinOffset = 4;
  static const _absinfoMaxOffset = 8;

  static DynamicLibrary? _libcCache;
  static bool _libcProbed = false;

  /// libc from the running process, or null when this is not Linux or the
  /// handle cannot be resolved. Probed once; the null answer is cached so
  /// a non-Linux host does not retry per device.
  static DynamicLibrary? _libc() {
    if (_libcProbed) return _libcCache;
    _libcProbed = true;
    try {
      _libcCache = Platform.isLinux ? DynamicLibrary.process() : null;
    } catch (_) {
      _libcCache = null;
    }
    return _libcCache;
  }

  /// The kernel's own per-axis travel range, read once at device open via
  /// the EVIOCGABS ioctl on [path].
  ///
  /// Returns `{axisCode: (min, max)}` for the axes that answered with a
  /// usable range. An EMPTY MAP IS THE FAILURE SIGNAL, not an error: the
  /// ioctl is refused by some devices, by some udev/permission setups, and
  /// unavailable entirely off Linux — callers fall back to widening the
  /// range from observed samples (see [absRange]). A separate handle is
  /// opened for the ioctl because dart:io does not expose the descriptor
  /// behind a [RandomAccessFile]; the node is opened read-only and closed
  /// again immediately, and no event is consumed (only ioctl is issued).
  static Map<int, (int, int)> readAbsRanges(String path) {
    final ranges = <int, (int, int)>{};
    final lib = _libc();
    if (lib == null) return ranges;

    late final void Function(Pointer<Void>) free;
    late final Pointer<Void> Function(int) malloc;
    late final int Function(Pointer<Void>, int) open;
    late final int Function(int) close;
    // ioctl is variadic in C; it is called here through a non-variadic
    // prototype. That is the standard FFI workaround and is safe for
    // glibc/musl, which read the third argument as a plain pointer.
    late final int Function(int, int, Pointer<Void>) ioctl;
    try {
      malloc = lib.lookupFunction<Pointer<Void> Function(IntPtr),
          Pointer<Void> Function(int)>('malloc');
      free = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('free');
      open = lib.lookupFunction<Int32 Function(Pointer<Void>, Int32),
          int Function(Pointer<Void>, int)>('open');
      close = lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
          'close');
      ioctl = lib.lookupFunction<
          Int32 Function(Int32, IntPtr, Pointer<Void>),
          int Function(int, int, Pointer<Void>)>('ioctl');
    } catch (_) {
      return ranges; // Symbol missing: treat as ioctl unavailable.
    }

    Pointer<Void>? pathPtr;
    Pointer<Void>? info;
    var fd = -1;
    try {
      final units = path.codeUnits;
      pathPtr = malloc(units.length + 1);
      if (pathPtr == nullptr) return ranges;
      final out = pathPtr.cast<Uint8>();
      for (var i = 0; i < units.length; i++) {
        out[i] = units[i];
      }
      out[units.length] = 0;
      fd = open(pathPtr, 0 /* O_RDONLY */);
      if (fd < 0) return ranges;
      info = malloc(_absinfoBytes);
      if (info == nullptr) return ranges;
      for (final code in absAxes) {
        final buf = info.cast<Uint8>();
        // Zero the struct: a driver that fills only part of it must not
        // leave stale bytes to be read as minimum/maximum.
        for (var i = 0; i < _absinfoBytes; i++) {
          buf[i] = 0;
        }
        if (ioctl(fd, evioCgabs(code), info) != 0) continue;
        final data = info.cast<Int32>();
        final lo = data[_absinfoMinOffset ~/ 4];
        final hi = data[_absinfoMaxOffset ~/ 4];
        if (hi <= lo) continue; // Unusable: keep the observed fallback.
        ranges[code] = (lo, hi);
      }
    } catch (_) {
      // Any failure at all leaves [ranges] as-is (possibly partial); the
      // caller treats a missing axis as "fall back to observed samples".
    } finally {
      if (info != null && info != nullptr) free(info);
      if (pathPtr != null && pathPtr != nullptr) free(pathPtr);
      if (fd >= 0) close(fd);
    }
    return ranges;
  }

  /// Pure helper: the effective (min, max) an absolute axis is normalized
  /// against, given the device's true range and the range observed so far.
  ///
  /// [deviceMin]/[deviceMax] come from EVIOCGABS and are null when that
  /// ioctl did not answer for this axis. When the device range is usable
  /// it wins outright, which is the whole point: a stick at rest (first
  /// sample 0) then normalizes against the axis's real travel, so the
  /// ratio maths is never degenerate and one anomalous spike at connect
  /// can no longer permanently widen the range until every later reading
  /// looks like a small ratio and latches a direction.
  ///
  /// Without a usable device range the observed window is used instead —
  /// the previous behaviour — and it is only meaningful once the axis has
  /// actually moved: at rest the window is zero-width and (0, 0) is
  /// returned, which [stickCode] reports as no direction rather than a
  /// spurious one.
  static (int, int) absRange({
    required int? deviceMin,
    required int? deviceMax,
    required int observedMin,
    required int observedMax,
  }) {
    if (deviceMin != null && deviceMax != null && deviceMax > deviceMin) {
      return (deviceMin, deviceMax);
    }
    if (observedMax > observedMin) return (observedMin, observedMax);
    return (0, 0);
  }

  /// Pure helper: the full absolute-axis decision — the ratio maths the
  /// device used inline, over the effective range from [absRange].
  ///
  /// This is the single seam the calibration tests exercise (no
  /// /dev/input needed): give it the kernel's true range (nulls when
  /// EVIOCGABS did not answer), the observed window so far, and the
  /// reading, and it returns the same code [stickCode] would for that
  /// range. Callers are expected to keep the observed window in sync
  /// exactly as [_EvdevDevice] does.
  static String? absStickCode({
    required int value,
    required int? deviceMin,
    required int? deviceMax,
    required int observedMin,
    required int observedMax,
    required String positive,
    required String negative,
  }) {
    final (lo, hi) = absRange(
      deviceMin: deviceMin,
      deviceMax: deviceMax,
      observedMin: observedMin,
      observedMax: observedMax,
    );
    return stickCode(value, lo, hi, positive, negative);
  }

  /// Pure helper: directional code for a stick axis value, or null inside
  /// the dead band. The value is normalized to 0..1 over [min]..[max];
  /// above 0.75 is the positive direction, below 0.25 the negative one,
  /// and between the two is no direction at all — that is a 50%-wide dead
  /// band centred on the middle, not a 50% threshold. A degenerate range
  /// ([max] <= [min]) also yields null. [positive]/[negative] are the
  /// vocab codes for the axis direction (e.g. right/left for X, down/up
  /// for Y).
  static String? stickCode(
      int value, int min, int max, String positive, String negative) {
    if (max <= min) return null;
    final ratio = (value - min) / (max - min);
    if (ratio > 0.75) return positive;
    if (ratio < 0.25) return negative;
    return null;
  }

  /// Pure helper: decodes a relative-axis event into (axis, delta), or
  /// null when the event is not a tracked EV_REL axis. EV_REL values are
  /// signed and unbounded, so they are passed through verbatim rather
  /// than thresholded (see [stickCode] for the absolute-axis case).
  static (String, int)? relDelta(int type, int code, int value) {
    if (type != evRel) return null;
    final axis = relCodes[code];
    if (axis == null) return null;
    return (axis, value);
  }

  void start(void Function(String code, bool pressed) onButton,
      void Function(bool connected, String name) onConnection, [
      void Function(String axis, int delta)? onPointer,
    ]) {
    if (_running) return;
    _running = true;
    _scan(onButton, onConnection, onPointer);
    _rescan = Timer.periodic(const Duration(seconds: 2),
        (_) => _running ? _scan(onButton, onConnection, onPointer) : null);
  }

  void _scan(void Function(String, bool) onButton,
      void Function(bool, String) onConnection,
      [void Function(String, int)? onPointer]) {
    for (var i = 0; i < 32; i++) {
      final path = '/dev/input/event$i';
      if (_devices.containsKey(path)) continue;
      RandomAccessFile? raf;
      try {
        raf = File(path).openSync(mode: FileMode.read);
      } catch (_) {
        continue; // No permission or not a device node.
      }
      final name = 'Gamepad ${path.split('/').last}';
      // Ask the kernel for each ABS axis's true travel range before the
      // first sample arrives. Best effort: readAbsRanges returns an empty
      // map when the ioctl is refused or the host is not Linux, and the
      // device then calibrates from observed samples as before.
      final dev = _EvdevDevice(path, raf,
          absRanges: LinuxEvdevPads.readAbsRanges(path));
      var announced = false;
      void announce() {
        if (!announced) {
          announced = true;
          _announced.add(path);
          onConnection(true, name);
        }
      }

      _devices[path] = dev;
      unawaited(
          _pump(dev, onButton, announce, onConnection, onPointer));
    }
  }

  Future<void> _pump(
      _EvdevDevice dev,
      void Function(String, bool) onButton,
      void Function() announce,
      void Function(bool, String) onConnection,
      [void Function(String, int)? onPointer]) async {
    try {
      while (_running && _devices[dev.path] == dev) {
        final bytes = await dev.raf.read(24 * 8);
        if (bytes.isEmpty) break; // Device gone.
        for (var off = 0; off + 24 <= bytes.length; off += 24) {
          final parsed = parseEvent(bytes, off);
          if (parsed == null) continue;
          dev.handle(parsed.$1, parsed.$2, parsed.$3, onButton, announce,
              onPointer);
        }
      }
    } catch (_) {
      // Read errors mean a disconnected device; fall through to cleanup.
    }
    final wasAnnounced = _announced.remove(dev.path);
    if (_devices.remove(dev.path) != null) {
      try {
        await dev.raf.close();
      } catch (_) {}
      if (wasAnnounced && _announced.isEmpty) onConnection(false, '');
    }
  }

  void stop() {
    _running = false;
    _rescan?.cancel();
    _rescan = null;
    for (final dev in _devices.values) {
      try {
        dev.raf.closeSync();
      } catch (_) {}
    }
    _devices.clear();
    _announced.clear();
  }
}

class _EvdevDevice {
  _EvdevDevice(this.path, this.raf, {Map<int, (int, int)>? absRanges})
      : deviceRanges = absRanges ?? const {};

  final String path;
  final RandomAccessFile raf;

  /// True per-axis travel range from EVIOCGABS at open, read once. An
  /// axis missing here (or absent entirely when the ioctl failed) falls
  /// back to widening [absMin]/[absMax] from observed samples.
  final Map<int, (int, int)> deviceRanges;
  final held = <String>{};
  final stickDirs = <String, String?>{};
  final absMin = <int, int>{};
  final absMax = <int, int>{};

  void handle(int type, int code, int value,
      void Function(String code, bool pressed) onButton,
      void Function() announce, [
      void Function(String axis, int delta)? onPointer,
    ]) {
    if (type == LinuxEvdevPads.evKey) {
      final mapped = LinuxEvdevPads.keyCodes[code];
      if (mapped == null) return;
      final down = value != 0;
      if (down && held.add(mapped)) {
        announce();
        onButton(mapped, true);
      } else if (!down && held.remove(mapped)) {
        onButton(mapped, false);
      }
      return;
    }
    if (type == LinuxEvdevPads.evRel) {
      // Pointer motion is NOT a gamepad signal: never a button, never an
      // announcement. Mouse and trackball nodes stream EV_REL constantly,
      // so feeding this to onButton/announce would present the desktop's
      // own pointer as a connected gamepad.
      final rel = LinuxEvdevPads.relDelta(type, code, value);
      if (rel == null) return;
      onPointer?.call(rel.$1, rel.$2);
      return;
    }
    if (type == LinuxEvdevPads.evAbs) {
      if (!LinuxEvdevPads.absAxes.contains(code)) return;
      // Observed window: seeded from the first sample, then only ever
      // widened. This is the FALLBACK path — it is what the kernel
      // range in [deviceRanges] exists to replace, and it stays the
      // behaviour whenever EVIOCGABS did not answer for this axis.
      absMin.putIfAbsent(code, () => value);
      absMax.putIfAbsent(code, () => value);
      if (value < absMin[code]!) absMin[code] = value;
      if (value > absMax[code]!) absMax[code] = value;
      final device = deviceRanges[code];
      final horizontal = code == 0 || code == 3;
      final mapped = LinuxEvdevPads.absStickCode(
        value: value,
        deviceMin: device?.$1,
        deviceMax: device?.$2,
        observedMin: absMin[code]!,
        observedMax: absMax[code]!,
        positive: horizontal ? 'right' : 'down',
        negative: horizontal ? 'left' : 'up',
      );
      final key = 'abs$code';
      final previous = stickDirs[key];
      if (mapped != previous) {
        if (previous != null && held.remove(previous)) {
          onButton(previous, false);
        }
        if (mapped != null && held.add(mapped)) {
          announce();
          onButton(mapped, true);
        }
        stickDirs[key] = mapped;
      }
      return;
    }
  }
}
