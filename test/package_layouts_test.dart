// Core packages can ship their own on-screen layouts (ADR-020). The same
// rules gate them at install (validator) and at play time (loader), the
// installer stages only what passes, and the player prefers: the user's own
// copy, then the core's layout, then the built-in.
import 'dart:convert';
import 'dart:io';

import 'package:ezcore/controls/builtin_layouts.dart';
import 'package:ezcore/controls/layout_store.dart';
import 'package:ezcore/controls/package_layouts.dart';
import 'package:ezcore/services/core_package_installer.dart';
import 'package:ezcore/services/core_package_validator.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> layout(String id, List<String> systems,
        {String orientation = 'portrait'}) =>
    {
      'format': 'ezcore.controls/1',
      'id': id,
      'name': 'Pkg $id',
      'systems': systems,
      'orientation': orientation,
      'screen': {'x': 0, 'y': 0, 'w': 1, 'h': 0.5},
      'controls': [
        {'id': 'menu', 'type': 'button', 'input': 'menu', 'x': 0.4, 'y': 0.55, 'w': 0.2, 'h': 0.05},
        {'id': 'a', 'type': 'button', 'input': 'a', 'x': 0.7, 'y': 0.7, 'w': 0.2, 'h': 0.2},
      ],
    };

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ezcore_pkglayouts'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Directory layoutsDir(Map<String, Object> files) {
    final d = Directory('${tmp.path}/layouts')..createSync(recursive: true);
    files.forEach((name, body) {
      if (body is Map) {
        File('${d.path}/$name').writeAsStringSync(jsonEncode(body));
      } else if (body == 'DIR') {
        Directory('${d.path}/$name').createSync();
      } else {
        File('${d.path}/$name').writeAsStringSync(body as String);
      }
    });
    return d;
  }

  group('readLayoutDir rules', () {
    test('valid layouts for declared systems are accepted', () {
      final r = readLayoutDir(
        layoutsDir({'gb.json': layout('pkg_gb', ['gb'])}),
        allowedSystems: ['gb', 'gbc'],
      );
      expect(r.errors, isEmpty);
      expect(r.layouts.single.$2.id, 'pkg_gb');
    });

    test('a layout for a system the core does not declare is refused', () {
      final r = readLayoutDir(
        layoutsDir({'psx.json': layout('hijack', ['psx'])}),
        allowedSystems: ['gb'],
      );
      expect(r.layouts, isEmpty);
      expect(r.errors.single, contains('does not declare'));
    });

    test('only flat .json files; invalid layouts named by file', () {
      final r = readLayoutDir(
        layoutsDir({
          'run.sh': 'echo hi',
          'nested': 'DIR',
          'broken.json': '{not json',
          'bad.json': {...layout('x', ['gb']), 'script': 'boom'},
        }),
        allowedSystems: ['gb'],
      );
      expect(r.layouts, isEmpty);
      expect(r.errors.join('\n'), allOf(
        contains('run.sh'),
        contains('nested'),
        contains('broken.json is not valid JSON'),
        contains('bad.json: unknown field "script"'),
      ));
    });

    test('duplicate ids and oversized files are refused', () {
      final r = readLayoutDir(
        layoutsDir({
          'a.json': layout('same', ['gb']),
          'b.json': layout('same', ['gb']),
          'big.json': ' ' * (maxLayoutBytes + 1),
        }),
        allowedSystems: ['gb'],
      );
      expect(r.layouts, hasLength(1));
      expect(r.errors.join('\n'), allOf(contains('repeats'), contains('larger')));
    });
  });

  group('install', () {
    Future<Directory> package(Map<String, Object> layouts) async {
      final pkg = Directory('${tmp.path}/pkgsrc/demo')..createSync(recursive: true);
      final lib = File('${pkg.path}/demo.${PackageInstaller.libraryExtension}')
        ..writeAsBytesSync(List.filled(64, 9));
      final pin = await const DartHashVerifier().sha256File(lib.path);
      File('${pkg.path}/manifest.json').writeAsStringSync(jsonEncode({
        'id': 'demo',
        'name': 'Demo',
        'version': '1.0',
        'license': 'MIT',
        'systems': ['gb'],
        'delivery': {Platform.operatingSystem: 'bundled'},
        'artifacts': {PackageInstaller.platformKey: pin},
      }));
      final ld = Directory('${pkg.path}/layouts')..createSync();
      layouts.forEach((n, b) =>
          File('${ld.path}/$n').writeAsStringSync(b is Map ? jsonEncode(b) : '$b'));
      return pkg;
    }

    test('a package with a bad layout does not validate', () async {
      final pkg = await package({'x.json': layout('x', ['psx'])});
      final report = await PackageValidationReport.validate(pkg);
      expect(report.ok, isFalse);
      expect(report.errors.join(), contains('does not declare'));
    });

    test('valid layouts are staged next to the core', () async {
      final pkg = await package({'gb.json': layout('pkg_gb', ['gb'])});
      final vault = Directory('${tmp.path}/vault');
      final report = await PackageInstaller().install(
        pkg,
        userConsented: true,
        vaultOverride: vault,
      );
      expect(report.ok, isTrue, reason: report.errors.join());
      expect(File('${vault.path}/cores/demo/layouts/gb.json').existsSync(),
          isTrue);
    });
  });

  group('player resolution', () {
    AppState stateWithPackage({bool landscapeOnly = false}) {
      final cores = Directory('${tmp.path}/cores/demo/layouts')
        ..createSync(recursive: true);
      File('${tmp.path}/cores/demo/manifest.json')
          .writeAsStringSync(jsonEncode({'id': 'demo', 'systems': ['gb']}));
      File('${cores.path}/gb.json').writeAsStringSync(jsonEncode(
          layout('pkg_gb', ['gb'], orientation: landscapeOnly ? 'landscape' : 'portrait')));
      return AppState.ephemeral()..coreRootPath = '${tmp.path}/cores';
    }

    test("the core's layout replaces the built-in for its games", () {
      final store = LayoutStore(stateWithPackage());
      final l = store.resolve('gb', portrait: true, coreId: 'demo');
      expect(l.id, 'pkg_gb');
      expect(store.resolve('gb', portrait: true, coreId: 'demo'), same(l));
      // Another core's games, or the other orientation, keep the built-in.
      expect(store.resolve('gb', portrait: true, coreId: 'other').id,
          builtinLayout('gb', portrait: true).id);
      expect(store.resolve('gb', portrait: false, coreId: 'demo').id,
          builtinLayout('gb', portrait: false).id);
    });

    test("the user's copy beats the core's, and reset returns to the core's",
        () async {
      final store = LayoutStore(stateWithPackage());
      final pkg = store.resolve('gb', portrait: true, coreId: 'demo');
      await store.save(pkg.copyWith(opacity: 0.3));
      expect(store.resolve('gb', portrait: true, coreId: 'demo').opacity, 0.3);
      await store.reset(pkg.id);
      expect(store.resolve('gb', portrait: true, coreId: 'demo').id, 'pkg_gb');
      expect(store.resolve('gb', portrait: true, coreId: 'demo').opacity, isNot(0.3));
    });
  });
}
