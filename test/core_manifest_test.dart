import 'package:flutter_test/flutter_test.dart';
import 'package:universal_emulator/models/core_manifest.dart';

CoreManifest _base() => const CoreManifest(
      id: 'mgba',
      name: 'mGBA',
      version: '0.10.5',
      license: 'MPL-2.0',
      systems: ['gba', 'gb', 'gbc'],
      extensions: ['gba', 'gb', 'gbc'],
      cheatFamilies: ['gba_actionreplay'],
      cheatsSupported: true,
      delivery: {'ios': 'bundled', 'android': 'download'},
      artifacts: {'macos-arm64': 'abc123'},
    );

void main() {
  test('valid manifest passes', () {
    expect(_base().validate(), isEmpty);
  });

  test('round-trips through json', () {
    final m = CoreManifest.fromJson(_base().toJson());
    expect(m.id, 'mgba');
    expect(m.systems, contains('gba'));
    expect(m.validate(), isEmpty);
  });

  test('ios download delivery is rejected', () {
    final m = CoreManifest.fromJson({
      ..._base().toJson(),
      'delivery': {'ios': 'download'},
    });
    expect(
      m.validate(),
      contains('ios delivery must be bundled or absent, never download'),
    );
  });

  test('blocked core must not ship artifacts', () {
    final m = CoreManifest.fromJson({
      ..._base().toJson(),
      'blocked_reason': 'legal hold',
      'artifacts': {'macos-arm64': 'abc123'},
    });
    expect(m.blocked, isTrue);
    expect(m.validate(), isNotEmpty);
  });

  test('missing fields are reported', () {
    const m = CoreManifest(
      id: '',
      name: '',
      version: '',
      license: '',
      systems: [],
      extensions: [],
      cheatFamilies: [],
      cheatsSupported: false,
      delivery: {},
      artifacts: {},
    );
    expect(m.validate().length, greaterThanOrEqualTo(5));
  });
}
