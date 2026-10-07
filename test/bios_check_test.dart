import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/services/bios_check.dart';

CoreManifest _manifest({bool needBios = true, List<String> files = const ['sys.pce', 'rom.bin']}) =>
    CoreManifest(
      id: 'probe',
      name: 'Probe',
      version: '1',
      license: 'MIT',
      systems: const ['pce'],
      extensions: const ['pce'],
      cheatFamilies: const [],
      cheatsSupported: false,
      delivery: const {},
      artifacts: const {},
      biosRequired: needBios,
      biosFiles: files,
    );

void main() {
  test('reports missing files with guidance', () async {
    final check = BiosCheck(fileExists: (_) => false, dirHasFiles: (_) => false);
    final report = await check.check(_manifest());
    expect(report.required, isTrue);
    expect(report.satisfied, isFalse);
    expect(report.missing, ['sys.pce', 'rom.bin']);
    expect(report.guidance, contains('sys.pce'));
    expect(report.guidance, contains('system'));
  });

  test('partial presence splits present and missing', () async {
    final check = BiosCheck(
      fileExists: (p) => p.endsWith('sys.pce'),
      dirHasFiles: (_) => false,
    );
    final report = await check.check(_manifest());
    expect(report.present, ['sys.pce']);
    expect(report.missing, ['rom.bin']);
  });

  test('cores without bios requirements always satisfy', () async {
    final check = BiosCheck(fileExists: (_) => false, dirHasFiles: (_) => false);
    final report = await check.check(_manifest(needBios: false, files: const []));
    expect(report.satisfied, isTrue);
    expect(report.guidance, isEmpty);
  });

  test('directory entries are satisfied only when they contain a file',
      () async {
    final check = BiosCheck(
      fileExists: (_) => false,
      dirHasFiles: (p) => p.endsWith('pcsx2/bios'),
    );
    final report = await check.check(_manifest(files: const ['pcsx2/bios']));
    expect(report.satisfied, isTrue);
    expect(report.present, ['pcsx2/bios']);
  });

  test('empty BIOS directory reports the full expected path', () async {
    final check = BiosCheck(fileExists: (_) => false, dirHasFiles: (_) => false);
    final report = await check.check(_manifest(files: const ['pcsx2/bios']));
    expect(report.satisfied, isFalse);
    expect(report.missing, ['pcsx2/bios']);
    expect(report.guidance, contains('system/pcsx2/bios'));
  });
}
