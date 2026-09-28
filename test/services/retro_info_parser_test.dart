// SPDX-License-Identifier: MIT
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/retro_info_parser.dart';

void main() {
  test('parses a well-formed info file', () {
    const info = '''
# FCEUmm core info
corename = "FCEUmm"
manufacturer = "libretro"
systemname = "Nintendo Entertainment System"
systemid = "nes"
supported_extensions = "nes|fds"
firmware_count = "1"
firmware0 = "disksys.rom"
some_unknown_key = "kept"
''';
    final r = RetroInfo.parse(info);
    expect(r.warnings, isEmpty);
    expect(r.name, 'FCEUmm');
    expect(r.manufacturer, 'libretro');
    expect(r.systemName, 'Nintendo Entertainment System');
    expect(r.systemId, 'nes');
    expect(r.supportedExtensions, ['nes', 'fds']);
    expect(r.firmwareCount, 1);
    expect(r.firmwareEntries, {'firmware0': 'disksys.rom'});
    expect(r.getValue('some_unknown_key'), 'kept');
  });

  test('comments and blank lines are ignored', () {
    const info = '''

# a comment

corename = "X"
''';
    final r = RetroInfo.parse(info);
    expect(r.warnings, isEmpty);
    expect(r.name, 'X');
    expect(r.entries, hasLength(1));
  });

  test('splits supported_extensions on pipe, preserves order', () {
    final r = RetroInfo.parse('supported_extensions = "nes|fds|unf|zip"');
    expect(r.supportedExtensions, ['nes', 'fds', 'unf', 'zip']);
  });

  test('handles escaped quotes inside values', () {
    const info = 'corename = "NES\\"Emu"\nsystemname = "A \\"B\\" C"';
    final r = RetroInfo.parse(info);
    expect(r.warnings, isEmpty);
    expect(r.name, 'NES"Emu');
    expect(r.systemName, 'A "B" C');
  });

  test('joins backslash-continued lines', () {
    const info = 'supported_extensions = "nes|\\\nfds"';
    final r = RetroInfo.parse(info);
    expect(r.warnings, isEmpty);
    expect(r.supportedExtensions, ['nes', 'fds']);
  });

  test('malformed lines and unterminated quotes produce warnings', () {
    const info = 'not an equals line\ncorename = "unterminated\nplain = text';
    final r = RetroInfo.parse(info);
    expect(r.warnings, isNotEmpty);
    expect(r.warnings.any((w) => w.contains('separator')), isTrue);
    expect(r.warnings.any((w) => w.contains('unterminated')), isTrue);
    // The unterminated value is not registered; parsing continued regardless.
    expect(r.name, isNull);
    expect(r.getValue('plain'), 'text');
  });

  test('non-integer firmware_count warns and falls back to entry count', () {
    const info = 'firmware_count = "abc"\nfirmware0 = "a"\nfirmware1 = "b"\n'
        'firmware2 = "c"';
    final r = RetroInfo.parse(info);
    expect(r.warnings.any((w) => w.contains('firmware_count')), isTrue);
    expect(r.firmwareCount, 3);
  });

  test('empty input yields nothing', () {
    final r = RetroInfo.parse('');
    expect(r.entries, isEmpty);
    expect(r.warnings, isEmpty);
    expect(r.name, isNull);
    expect(r.supportedExtensions, isEmpty);
    expect(r.firmwareCount, 0);
  });

  test('supportedExtensions empty when absent', () {
    final r = RetroInfo.parse('corename = "X"');
    expect(r.supportedExtensions, isEmpty);
  });

  test('unquoted values are accepted', () {
    final r = RetroInfo.parse('corename = plainname');
    expect(r.name, 'plainname');
    expect(r.warnings, isEmpty);
  });
}
