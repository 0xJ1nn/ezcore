import 'dart:async';
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
/// normalizes against per-axis observed extremes with a 50% threshold.
class LinuxEvdevPads {
  LinuxEvdevPads();

  bool _running = false;
  Timer? _rescan;
  final _devices = <String, _EvdevDevice>{};
  final _announced = <String>{};

  static const evKey = 1;
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

  /// Pure helper: decodes one 24-byte input_event into (type, code, value).
  static (int, int, int)? parseEvent(Uint8List bytes, [int offset = 0]) {
    if (bytes.length - offset < 24) return null;
    final data = ByteData.sublistView(bytes, offset, offset + 24);
    final type = data.getUint16(16, Endian.host);
    final code = data.getUint16(18, Endian.host);
    final value = data.getInt32(20, Endian.host);
    return (type, code, value);
  }

  /// Pure helper: directional code for a stick axis value, or null inside
  /// the 50% dead band. [positive]/[negative] are the vocab codes for the
  /// axis direction (e.g. right/left for X, down/up for Y).
  static String? stickCode(
      int value, int min, int max, String positive, String negative) {
    if (max <= min) return null;
    final ratio = (value - min) / (max - min);
    if (ratio > 0.75) return positive;
    if (ratio < 0.25) return negative;
    return null;
  }

  void start(void Function(String code, bool pressed) onButton,
      void Function(bool connected, String name) onConnection) {
    if (_running) return;
    _running = true;
    _scan(onButton, onConnection);
    _rescan = Timer.periodic(const Duration(seconds: 2),
        (_) => _running ? _scan(onButton, onConnection) : null);
  }

  void _scan(void Function(String, bool) onButton,
      void Function(bool, String) onConnection) {
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
      final dev = _EvdevDevice(path, raf);
      var announced = false;
      void announce() {
        if (!announced) {
          announced = true;
          _announced.add(path);
          onConnection(true, name);
        }
      }

      _devices[path] = dev;
      unawaited(_pump(dev, onButton, announce, onConnection));
    }
  }

  Future<void> _pump(
      _EvdevDevice dev,
      void Function(String, bool) onButton,
      void Function() announce,
      void Function(bool, String) onConnection) async {
    try {
      while (_running && _devices[dev.path] == dev) {
        final bytes = await dev.raf.read(24 * 8);
        if (bytes.isEmpty) break; // Device gone.
        for (var off = 0; off + 24 <= bytes.length; off += 24) {
          final parsed = parseEvent(bytes, off);
          if (parsed == null) continue;
          dev.handle(parsed.$1, parsed.$2, parsed.$3, onButton, announce);
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
  _EvdevDevice(this.path, this.raf);

  final String path;
  final RandomAccessFile raf;
  final held = <String>{};
  final stickDirs = <String, String?>{};
  final absMin = <int, int>{};
  final absMax = <int, int>{};

  void handle(int type, int code, int value,
      void Function(String code, bool pressed) onButton,
      void Function() announce) {
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
    if (type == LinuxEvdevPads.evAbs) {
      if (!LinuxEvdevPads.absAxes.contains(code)) return;
      absMin.putIfAbsent(code, () => value);
      absMax.putIfAbsent(code, () => value);
      if (value < absMin[code]!) absMin[code] = value;
      if (value > absMax[code]!) absMax[code] = value;
      final lo = absMin[code]!;
      final hi = absMax[code]!;
      final horizontal = code == 0 || code == 3;
      final mapped = LinuxEvdevPads.stickCode(
        value,
        lo,
        hi,
        horizontal ? 'right' : 'down',
        horizontal ? 'left' : 'up',
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
