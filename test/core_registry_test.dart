import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_emulator/cores/core_registry.dart';
import 'package:universal_emulator/models/core_manifest.dart';

String _json(CoreManifest m) => json.encode(m.toJson());

CoreManifest _mgba() => const CoreManifest(
      id: 'mgba',
      name: 'mGBA',
      version: '0.10.5',
      license: 'MPL-2.0',
      systems: ['gba'],
      extensions: ['gba'],
      cheatFamilies: ['gba_actionreplay'],
      cheatsSupported: true,
      delivery: {'ios': 'bundled'},
      artifacts: {'macos-arm64': 'sha-mgba'},
    );

CoreManifest _blocked() => const CoreManifest(
      id: 'switch_tainted',
      name: 'Tainted Switch core',
      version: '0.0.0',
      license: 'GPL-3.0',
      systems: ['switch'],
      extensions: ['nsp'],
      cheatFamilies: [],
      cheatsSupported: false,
      delivery: {'ios': 'absent'},
      artifacts: {},
      blockedReason: 'requires prod.keys + TPM circumvention (DMCA 1201)',
    );

void main() {
  test('install / update / remove round-trip', () {
    final reg = CoreRegistry();
    final errors = reg.loadCatalog({'mgba': _json(_mgba())});
    expect(errors, isEmpty);
    expect(reg.statusOf(_mgba()), CoreStatus.notInstalled);

    reg.install(_mgba(), expectedSha256: 'sha-mgba');
    expect(reg.isInstalled('mgba'), isTrue);

    final newer = CoreManifest.fromJson({
      ..._mgba().toJson(),
      'version': '0.10.6',
      'artifacts': {'macos-arm64': 'sha-mgba2'},
    });
    reg.loadCatalog({'mgba': json.encode(newer.toJson())});
    expect(reg.statusOf(newer), CoreStatus.updateAvailable);
    reg.update(newer, expectedSha256: 'sha-mgba2');
    expect(reg.statusOf(newer), CoreStatus.installed);

    expect(reg.remove('mgba'), 0);
    expect(reg.isInstalled('mgba'), isFalse);
  });

  test('unpinned hash is refused', () {
    final reg = CoreRegistry();
    reg.loadCatalog({'mgba': _json(_mgba())});
    expect(
      () => reg.install(_mgba(), expectedSha256: 'evil'),
      throwsStateError,
    );
  });

  test('blocked core cannot install', () {
    final reg = CoreRegistry();
    reg.loadCatalog({'switch_tainted': _json(_blocked())});
    expect(reg.statusOf(_blocked()), CoreStatus.blocked);
    expect(
      () => reg.install(_blocked(), expectedSha256: 'x'),
      throwsStateError,
    );
  });

  test('compatibleCores matches installed extensions only', () {
    final reg = CoreRegistry();
    reg.loadCatalog({'mgba': _json(_mgba())});
    expect(reg.compatibleCores('gba'), isEmpty);
    reg.install(_mgba(), expectedSha256: 'sha-mgba');
    expect(reg.compatibleCores('.GBA').map((m) => m.id), ['mgba']);
    expect(reg.compatibleCores('sfc'), isEmpty);
  });

  test('malformed manifest is reported, not thrown', () {
    final reg = CoreRegistry();
    final errors = reg.loadCatalog({'broken': '{nope'});
    expect(errors.keys, ['broken']);
    expect(reg.catalog, isEmpty);
  });
}
