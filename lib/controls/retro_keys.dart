import 'package:flutter/services.dart';

/// Flutter keys as libretro RETROK_* codes, for cores that read a keyboard
/// (DOS, adventure games, computers). Values are taken from the vendored
/// libretro.h; test/retro_keys_test.dart re-checks them against it.
final Map<LogicalKeyboardKey, int> retroKeys = {
  LogicalKeyboardKey.backspace: 8,
  LogicalKeyboardKey.tab: 9,
  LogicalKeyboardKey.enter: 13,
  LogicalKeyboardKey.escape: 27,
  LogicalKeyboardKey.space: 32,
  LogicalKeyboardKey.quote: 39,
  LogicalKeyboardKey.comma: 44,
  LogicalKeyboardKey.minus: 45,
  LogicalKeyboardKey.period: 46,
  LogicalKeyboardKey.slash: 47,
  for (var i = 0; i <= 9; i++)
    LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + i): 48 + i,
  LogicalKeyboardKey.semicolon: 59,
  LogicalKeyboardKey.equal: 61,
  LogicalKeyboardKey.bracketLeft: 91,
  LogicalKeyboardKey.backslash: 92,
  LogicalKeyboardKey.bracketRight: 93,
  LogicalKeyboardKey.backquote: 96,
  for (var i = 0; i < 26; i++)
    LogicalKeyboardKey(LogicalKeyboardKey.keyA.keyId + i): 97 + i,
  LogicalKeyboardKey.delete: 127,
  LogicalKeyboardKey.numpad0: 256,
  LogicalKeyboardKey.numpad1: 257,
  LogicalKeyboardKey.numpad2: 258,
  LogicalKeyboardKey.numpad3: 259,
  LogicalKeyboardKey.numpad4: 260,
  LogicalKeyboardKey.numpad5: 261,
  LogicalKeyboardKey.numpad6: 262,
  LogicalKeyboardKey.numpad7: 263,
  LogicalKeyboardKey.numpad8: 264,
  LogicalKeyboardKey.numpad9: 265,
  LogicalKeyboardKey.numpadDecimal: 266,
  LogicalKeyboardKey.numpadDivide: 267,
  LogicalKeyboardKey.numpadMultiply: 268,
  LogicalKeyboardKey.numpadSubtract: 269,
  LogicalKeyboardKey.numpadAdd: 270,
  LogicalKeyboardKey.numpadEnter: 271,
  LogicalKeyboardKey.arrowUp: 273,
  LogicalKeyboardKey.arrowDown: 274,
  LogicalKeyboardKey.arrowRight: 275,
  LogicalKeyboardKey.arrowLeft: 276,
  LogicalKeyboardKey.insert: 277,
  LogicalKeyboardKey.home: 278,
  LogicalKeyboardKey.end: 279,
  LogicalKeyboardKey.pageUp: 280,
  LogicalKeyboardKey.pageDown: 281,
  LogicalKeyboardKey.f1: 282,
  LogicalKeyboardKey.f2: 283,
  LogicalKeyboardKey.f3: 284,
  LogicalKeyboardKey.f4: 285,
  LogicalKeyboardKey.f5: 286,
  LogicalKeyboardKey.f6: 287,
  LogicalKeyboardKey.f7: 288,
  LogicalKeyboardKey.f8: 289,
  LogicalKeyboardKey.f9: 290,
  LogicalKeyboardKey.f10: 291,
  LogicalKeyboardKey.f11: 292,
  LogicalKeyboardKey.numLock: 300,
  LogicalKeyboardKey.capsLock: 301,
  LogicalKeyboardKey.scrollLock: 302,
  LogicalKeyboardKey.shiftRight: 303,
  LogicalKeyboardKey.shiftLeft: 304,
  LogicalKeyboardKey.controlRight: 305,
  LogicalKeyboardKey.controlLeft: 306,
  LogicalKeyboardKey.altRight: 307,
  LogicalKeyboardKey.altLeft: 308,
  LogicalKeyboardKey.metaLeft: 311,
  LogicalKeyboardKey.metaRight: 312,
};

/// RETROKMOD_* bits for the modifiers currently held.
int retroModifiers() {
  final k = HardwareKeyboard.instance;
  return (k.isShiftPressed ? 0x01 : 0) |
      (k.isControlPressed ? 0x02 : 0) |
      (k.isAltPressed ? 0x04 : 0) |
      (k.isMetaPressed ? 0x08 : 0);
}

/// Systems played mainly with a keyboard and mouse. In their games every key
/// goes to the core as a key (the arrows are not also a d-pad), and the
/// pause menu moves from Esc — which these games use — to F12. This is
/// system data, never a core name.
const keyboardFirstSystems = {'dos', 'scumm', 'pc', 'amiga', 'c64', 'msx'};
