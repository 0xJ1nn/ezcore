import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/cheat.dart';

const sample = '''
cheats = 2

[cheat0]
desc = "Infinite lives"
code = "0101ABCD"
enable = true

[cheat1]
desc = "Moon jump"
code = "0111EF02"
code = "0222AA10"
enable = false
''';

void main() {
  test('parses sections, codes, flags', () {
    final cheats = parseCht(sample);
    expect(cheats.length, 2);
    expect(cheats[0].desc, 'Infinite lives');
    expect(cheats[0].code, '0101ABCD');
    expect(cheats[0].enabled, isTrue);
    expect(cheats[1].code.split('\n').length, 2);
    expect(cheats[1].enabled, isFalse);
  });

  test('skips sections without codes', () {
    expect(parseCht('[cheat0]\ndesc = "empty"\n'), isEmpty);
  });

  test('round-trips serialize -> parse', () {
    final once = parseCht(sample);
    final twice = parseCht(serializeCht(once));
    expect(twice.length, once.length);
    expect(twice[0].desc, once[0].desc);
    expect(twice[0].code, once[0].code);
    expect(twice[0].enabled, once[0].enabled);
  });

  test('parses flat libretro-database keys', () {
    const flat = '''
cheats = 2
cheat0_desc = "Infinite lives"
cheat0_code = "0101ABCD"
cheat0_enable = true
cheat1_desc = "Moon jump"
cheat1_code = "0111EF02"
cheat1_code = "0222AA10"
cheat1_enable = false
''';
    final cheats = parseCht(flat);
    expect(cheats.length, 2);
    expect(cheats[0].desc, 'Infinite lives');
    expect(cheats[0].enabled, isTrue);
    expect(cheats[1].code.split('\n').length, 2);
    expect(cheats[1].enabled, isFalse);
    // Serialized output is itself flat-format (ecosystem round-trip).
    expect(serializeCht(cheats), contains('cheat1_code = "0222AA10"'));
  });
}
