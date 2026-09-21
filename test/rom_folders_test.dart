import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/state/app_state.dart';

const _mgbaManifest = '''
{
  "id": "mgba",
  "name": "mGBA",
  "version": "0.11-dev",
  "license": "MPL-2.0",
  "systems": ["gba"],
  "extensions": ["gba", "zip"],
  "cheat_families": [],
  "cheats_supported": false,
  "delivery": {"linux": "bundled"},
  "artifacts": {}
}
''';

/// Creates a fake ROM file with valid GBA magic bytes (at 0x04, where the
/// real Nintendo logo lives inside the cart).
Future<File> createFakeRom(Directory dir, String name, {int size = 4096}) async {
  final file = File('${dir.path}/$name.gba');
  final bytes = Uint8List(size);
  // GBA magic: 0x24 0xFF 0xAE 0x51 0x69 0x9A 0xA2 0x21 at offset 0x04
  final magic = [0x24, 0xFF, 0xAE, 0x51, 0x69, 0x9A, 0xA2, 0x21];
  for (var i = 0; i < magic.length; i++) {
    bytes[0x04 + i] = magic[i];
  }
  for (var i = 0x04 + magic.length; i < size; i++) {
    bytes[i] = 0xFF;
  }
  await file.writeAsBytes(bytes);
  return file;
}

void main() {
  late Directory tmpDir;
  late AppState state;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ezcore_romfolders');
    state = AppState.ephemeral();
    final errors = state.registry.loadCatalog({'mgba': _mgbaManifest});
    expect(errors, isEmpty);
  });

  tearDown(() async {
    state.dispose();
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  test('rescan adds nested-folder games with their core assigned', () async {
    final sub = Directory('${tmpDir.path}/Nintendo - GBA/inner');
    await sub.create(recursive: true);
    await createFakeRom(sub, 'supertux');
    await state.addRomFolder('${tmpDir.path}/Nintendo - GBA');

    final report = await state.rescanRomFolders();

    expect(report.added, 1);
    expect(report.foldersScanned, 1);
    expect(state.games, hasLength(1));
    expect(state.games.first.title, 'supertux.gba');
    expect(state.games.first.coreId, 'mgba');
    expect(state.games.first.system, 'gba');
  });

  test('second rescan adds nothing (hash dedup)', () async {
    await createFakeRom(tmpDir, 'game');
    await state.addRomFolder(tmpDir.path);

    final first = await state.rescanRomFolders();
    final second = await state.rescanRomFolders();

    expect(first.added, 1);
    expect(second.added, 0);
    expect(second.pruned, 0);
    expect(state.games, hasLength(1));
  });

  test('prunes files deleted while their folder still exists', () async {
    final file = await createFakeRom(tmpDir, 'gone');
    await state.addRomFolder(tmpDir.path);
    await state.rescanRomFolders();
    expect(state.games, hasLength(1));

    await file.delete();
    final report = await state.rescanRomFolders();

    expect(report.pruned, 1);
    expect(state.games, isEmpty);
  });

  test('never prunes when the whole folder is gone (unplugged drive)',
      () async {
    final folder = Directory('${tmpDir.path}/usb');
    await folder.create();
    await createFakeRom(folder, 'game');
    await state.addRomFolder(folder.path);
    await state.rescanRomFolders();
    expect(state.games, hasLength(1));

    await folder.delete(recursive: true);
    final report = await state.rescanRomFolders();

    expect(report.pruned, 0);
    expect(report.foldersScanned, 0);
    expect(state.games, hasLength(1));
  });

  test('romFolders round-trips through add/remove without duplicates',
      () async {
    await state.addRomFolder('/a');
    await state.addRomFolder('/b');
    await state.addRomFolder('/a');
    expect(state.romFolders, ['/a', '/b']);
    await state.removeRomFolder('/a');
    expect(state.romFolders, ['/b']);
  });

  test('rescan with no folders is a no-op', () async {
    final report = await state.rescanRomFolders();
    expect(report.changed, isFalse);
    expect(state.games, isEmpty);
  });

  test('rejects text files with ROM extensions during rescan', () async {
    await File('${tmpDir.path}/README.txt').writeAsString('not a rom');
    await createFakeRom(tmpDir, 'game');
    await state.addRomFolder(tmpDir.path);

    final report = await state.rescanRomFolders();

    expect(report.added, 1);
    expect(state.games, hasLength(1));
    expect(state.games.first.title, 'game.gba');
  });
}
