import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/state/save_sync.dart';

Future<void> _exercise(SaveSyncProvider provider) async {
  expect(await provider.list('game-1'), isEmpty);
  expect(await provider.download('game-1', 'auto'), isNull);

  await provider.upload(
    'game-1',
    'auto',
    Uint8List.fromList([1, 2, 3, 4]),
  );
  await provider.upload(
    'game-1',
    'slot-0',
    Uint8List.fromList([9, 9]),
  );

  final slots = await provider.list('game-1');
  expect(slots.map((s) => s.id).toSet(), {'auto', 'slot-0'});
  expect(await provider.download('game-1', 'auto'), [1, 2, 3, 4]);

  await provider.remove('game-1', 'auto');
  expect(await provider.download('game-1', 'auto'), isNull);
  expect((await provider.list('game-1')).map((s) => s.id), ['slot-0']);
}

void main() {
  test('memory provider round-trips', () async {
    await _exercise(MemorySaveSyncProvider());
  });

  test('local provider round-trips on disk', () async {
    final root = await Directory.systemTemp.createTemp('ezcore_saves');
    try {
      final provider = LocalSaveSyncProvider(root);
      expect(provider.id, 'local');
      await _exercise(provider);
    } finally {
      await root.delete(recursive: true);
    }
  });
}
