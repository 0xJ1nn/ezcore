// The package-install discovery round trip (P2 integration): install a
// package into a vault, then discovery must register it as a user package —
// exactly the path app_state.load()/rediscoverCores() run.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/cores/core_registry.dart';
import 'package:ezcore/services/core_discovery.dart';
import 'package:ezcore/services/core_package_installer.dart';
import 'package:ezcore/services/hash_verifier.dart';

void main() {
  test(
    'installed packages register through discovery as unverified user cores',
    () async {
      final base = await Directory.systemTemp.createTemp('ezcore_pkg_disc');
      final vault = await Directory.systemTemp.createTemp('ezcore_vault_disc');
      final registry = CoreRegistry();
      try {
        final pkg = Directory('${base.path}/discodroid');
        await pkg.create(recursive: true);
        final ext = PackageInstaller.libraryExtension;
        final libBytes = List<int>.filled(64, 0x5A);
        final libFile = File('${pkg.path}/discodroid.$ext');
        await libFile.writeAsBytes(libBytes);
        final sha = await const DartHashVerifier().sha256File(libFile.path);
        final manifest = <String, dynamic>{
          'id': 'discodroid',
          'name': 'DiscoDroid',
          'version': '0.1.0',
          'license': 'MIT',
          'license_url': 'https://example.invalid/LICENSE',
          'homepage': 'https://example.invalid',
          'upstream': 'example/discodroid',
          'systems': <String>['test'],
          'extensions': <String>['bin'],
          'delivery': <String, String>{
            'linux': 'bundled',
            'macos': 'bundled',
            'windows': 'bundled',
          },
          'artifacts': <String, String>{PackageInstaller.platformKey: sha},
        };
        await File(
          '${pkg.path}/manifest.json',
        ).writeAsString(jsonEncode(manifest));

        final report = await PackageInstaller().install(
          pkg,
          userConsented: true,
          vaultOverride: vault,
        );
        expect(report.ok, isTrue, reason: report.errors.join(', '));

        // Before discovery the registry does not know the package.
        expect(registry.isInstalled('discodroid'), isFalse);

        // The vault is the discovery root — the same object app_state.load()
        // hands to CoreDiscovery.
        final discovery = CoreDiscovery(Directory('${vault.path}/cores'));
        await discovery.discover(registry);

        expect(registry.isInstalled('discodroid'), isTrue);
        expect(registry.isUserPackage('discodroid'), isTrue);
        expect(
          registry.catalog.where((m) => m.id == 'discodroid').length,
          1,
          reason: 'no duplicate registration on re-discovery',
        );

        // Idempotent: running discovery again neither duplicates nor errors.
        final again = await discovery.discover(registry);
        expect(again.containsKey('discodroid'), isTrue);
        expect(registry.catalog.where((m) => m.id == 'discodroid').length, 1);
        expect(discovery.errors, isEmpty);
      } finally {
        await base.delete(recursive: true);
        await vault.delete(recursive: true);
      }
    },
  );
}
