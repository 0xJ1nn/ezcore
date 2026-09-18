import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/gamepad.dart';
import 'package:ezcore/services/gamepad_linux.dart';
import 'package:ezcore/services/gamepad_windows.dart';

void main() {
  test('canonical codes map to RetroPad ids 0-15', () {
    const expected = {
      'b': 0, 'y': 1, 'select': 2, 'start': 3,
      'up': 4, 'down': 5, 'left': 6, 'right': 7,
      'a': 8, 'x': 9, 'lb': 10, 'rb': 11,
      'lt': 12, 'rt': 13, 'l3': 14, 'r3': 15,
    };
    expected.forEach((code, id) {
      expect(GamepadService.toRetroPad(code), id, reason: code);
      expect(GamepadEvent(code, true).retroPadId, id, reason: code);
    });
    expect(GamepadService.toRetroPad('guide'), isNull);
    expect(GamepadService.toRetroPad(''), isNull);
  });

  test('channel button calls surface as events', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final service = GamepadService();
    final received = <GamepadEvent>[];
    final cancel = service.onButton(received.add);
    const codec = StandardMethodCodec();
    Future<void> send(String method, Map<String, Object?> args) {
      final completer = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'ezcore/gamepad',
        codec.encodeMethodCall(MethodCall(method, args)),
        (_) => completer.complete(),
      );
      return completer.future;
    }

    await send('button', {'code': 'a', 'pressed': true});
    await send('button', {'code': 'nope', 'pressed': true});
    await send('button', {'code': 'start', 'pressed': false});
    expect(received.map((e) => e.code), ['a', 'nope', 'start']);
    expect(received.map((e) => e.retroPadId), [8, isNull, 3]);
    cancel();
    service.dispose();
  });

  test('connection calls track the pad name', () async {    TestWidgetsFlutterBinding.ensureInitialized();
    final service = GamepadService();
    expect(service.connectedPad, isNull);
    String? last;
    final cancel = service.onConnection((_, name) => last = name);
    const codec = StandardMethodCodec();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      'ezcore/gamepad',
      codec.encodeMethodCall(const MethodCall(
          'connection', {'connected': true, 'name': 'Pad Pro'})),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.connectedPad, 'Pad Pro');
    expect(last, 'Pad Pro');
    cancel();
    service.dispose();
  });

  test('xinput masks decode to vocab codes', () {
    expect(
      WindowsXInputPoller.codesFor(
        buttons: 0x1000 | 0x0001 | 0x0200,
        leftTrigger: 0,
        rightTrigger: 200,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ),
      {'a', 'up', 'rb', 'rt'},
    );
    // Stick threshold + trigger gate.
    expect(
      WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: 10,
        rightTrigger: 0,
        lx: 20000,
        ly: -20000,
        rx: 100,
        ry: 100,
      ),
      {'right', 'down'},
    );
    expect(
      WindowsXInputPoller.codesFor(
        buttons: 0,
        leftTrigger: 0,
        rightTrigger: 0,
        lx: 0,
        ly: 0,
        rx: 0,
        ry: 0,
      ),
      isEmpty,
    );
  });

  test('evdev events decode and sticks threshold', () {
    // type=EV_KEY(1) code=BTN_SOUTH(304) value=1.
    final down = ByteData(24);
    down.setUint16(16, 1, Endian.host);
    down.setUint16(18, 304, Endian.host);
    down.setInt32(20, 1, Endian.host);
    expect(
      LinuxEvdevPads.parseEvent(down.buffer.asUint8List()),
      (1, 304, 1),
    );
    expect(LinuxEvdevPads.parseEvent(Uint8List(10)), isNull);
    // Axis 0 spanning 0..255: extremes deflect, center rests.
    expect(LinuxEvdevPads.stickCode(255, 0, 255, 'right', 'left'), 'right');
    expect(LinuxEvdevPads.stickCode(0, 0, 255, 'right', 'left'), 'left');
    expect(LinuxEvdevPads.stickCode(128, 0, 255, 'right', 'left'), isNull);
    expect(LinuxEvdevPads.stickCode(5, 5, 5, 'right', 'left'), isNull);
  });
}
