import 'dart:io';

import 'package:ezcore/controls/retro_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('key codes match the vendored libretro.h', () {
    final h = File('runtime/external/libretro-common/include/libretro.h')
        .readAsStringSync();
    int code(String name) => int.parse(
        RegExp('RETROK_$name\\s*=\\s*(\\d+)').firstMatch(h)!.group(1)!);
    expect(retroKeys[LogicalKeyboardKey.escape], code('ESCAPE'));
    expect(retroKeys[LogicalKeyboardKey.keyA], code('a'));
    expect(retroKeys[LogicalKeyboardKey.keyZ], code('z'));
    expect(retroKeys[LogicalKeyboardKey.digit9], code('9'));
    expect(retroKeys[LogicalKeyboardKey.arrowLeft], code('LEFT'));
    expect(retroKeys[LogicalKeyboardKey.f11], code('F11'));
    expect(retroKeys[LogicalKeyboardKey.numpadEnter], code('KP_ENTER'));
    expect(retroKeys[LogicalKeyboardKey.shiftLeft], code('LSHIFT'));
    expect(retroKeys[LogicalKeyboardKey.metaRight], code('RSUPER'));
  });

  test('F12 is free for the pause menu in keyboard-first games', () {
    expect(retroKeys.containsKey(LogicalKeyboardKey.f12), isFalse);
  });
}
