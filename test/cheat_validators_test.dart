import 'package:flutter_test/flutter_test.dart';
import 'package:universal_emulator/cores/cheat_validators.dart';

void main() {
  test('known-good shapes validate', () {
    expect(CheatValidators.validate('gb_gameshark', '0101ABCD'), isNull);
    expect(
      CheatValidators.validate('gba_actionreplay', '03005C08000000FF'),
      isNull,
    );
    expect(
      CheatValidators.validate('snes_gamegenie', 'C2A5-DF0F'),
      isNull,
    );
    expect(
      CheatValidators.validate('psp_cwcheat', '_L 0x003B5260 0x00000063'),
      isNull,
    );
    expect(
      CheatValidators.validate('gba_gameshark', '03005C08000000FF\n1234ABCD87654321'),
      isNull,
    );
  });

  test('bad lines fail with line numbers', () {
    expect(
      CheatValidators.validate('gb_gameshark', 'ZZZZ'),
      contains('Line 1'),
    );
    expect(
      CheatValidators.validate('gb_gameshark', '0101ABCD\nnope'),
      contains('Line 2'),
    );
  });

  test('unknown families and empty codes fail closed', () {
    expect(
      CheatValidators.validate('ps5_something', '1234'),
      contains('Unknown'),
    );
    expect(CheatValidators.validate('gb_gameshark', '   '), contains('empty'));
  });
}
