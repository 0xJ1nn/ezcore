import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/core_manifest.dart';

CoreManifest _base() => const CoreManifest(
      id: 'advancebit',
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

  test('bios entries are normalized to bare filenames', () {
    // Manifests historically carried notes in parentheses after the name;
    // those can never match a file on disk, so parsing strips them.
    final m = CoreManifest.fromJson({
      'id': 'probe',
      'name': 'Probe',
      'version': '1',
      'license': 'MIT',
      'systems': ['pce'],
      'extensions': ['pce'],
      'bios_required': true,
      'bios_files': [
        'syscard3.pce (CD titles only, user-supplied, hash-gated)',
        'sega_101.bin',
      ],
    });
    expect(m.biosFiles, ['syscard3.pce', 'sega_101.bin']);
  });

  test('round-trips through json', () {
    final m = CoreManifest.fromJson(_base().toJson());
    expect(m.id, 'advancebit');
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
      'blocked_reason': 'on hold',
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

  test('execution strategies validate, ios rejects dynarec', () {
    final ok = CoreManifest.fromJson({
      ..._base().toJson(),
      'execution': {'ios': 'interpreter', 'android': 'dynarec'},
    });
    expect(ok.validate(), isEmpty);
    expect(ok.executionFor('ios'), 'interpreter');
    expect(ok.executionFor('windows'), 'unknown');

    final badOs = CoreManifest.fromJson({
      ..._base().toJson(),
      'execution': {'ios': 'dynarec'},
    });
    expect(badOs.validate(), isNotEmpty);
  });
}
