import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/cheat.dart';
import 'package:ezcore/models/game_entry.dart';

void main() {
  group('GameEntry JSON', () {
    test('round-trips through fromJson/toJson', () {
      const original = GameEntry(
        id: 'g1',
        title: 'Tobu Tobu Girl (homebrew)',
        system: 'gb',
        filePath: '/Users/me/games/tobutobu.gb',
        extension: 'gb',
        fileSize: 131072,
        sha1: 'abc123',
        favorite: true,
        coreId: 'sameboy',
        lastPlayedMs: 1725900000000,
        cheatsOn: 2,
        stateCount: 3,
      );
      final json = original.toJson();
      final restored = GameEntry.fromJson(json);
      expect(restored, original);
      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.system, original.system);
      expect(restored.filePath, original.filePath);
      expect(restored.extension, original.extension);
      expect(restored.fileSize, original.fileSize);
      expect(restored.sha1, original.sha1);
      expect(restored.favorite, original.favorite);
      expect(restored.coreId, original.coreId);
      expect(restored.lastPlayedMs, original.lastPlayedMs);
      expect(restored.cheatsOn, original.cheatsOn);
      expect(restored.stateCount, original.stateCount);
    });

    test('fromJson tolerates missing fields with defaults', () {
      final restored = GameEntry.fromJson({});
      expect(restored.id, '');
      expect(restored.title, '');
      expect(restored.system, '');
      expect(restored.filePath, '');
      expect(restored.extension, '');
      expect(restored.fileSize, 0);
      expect(restored.sha1, '');
      expect(restored.favorite, false);
      expect(restored.coreId, '');
      expect(restored.lastPlayedMs, 0);
      expect(restored.cheatsOn, 0);
      expect(restored.stateCount, 0);
    });

    test('toJson survives JSON encode/decode', () {
      const entry = GameEntry(
        id: 'g1',
        title: 'Test',
        system: 'gb',
        filePath: '/foo/bar.gb',
        extension: 'gb',
      );
      final encoded = json.encode(entry.toJson());
      final decoded = json.decode(encoded) as Map<String, dynamic>;
      expect(GameEntry.fromJson(decoded), entry);
    });
  });

  group('CheatEntry JSON', () {
    test('round-trips through fromJson/toJson', () {
      const original = CheatEntry(
        index: 0,
        desc: 'Infinite lives',
        code: 'DEADBEEF',
        enabled: true,
      );
      final json = original.toJson();
      final restored = CheatEntry.fromJson(json);
      expect(restored.index, original.index);
      expect(restored.desc, original.desc);
      expect(restored.code, original.code);
      expect(restored.enabled, original.enabled);
    });

    test('fromJson tolerates missing fields with defaults', () {
      final restored = CheatEntry.fromJson({});
      expect(restored.index, 0);
      expect(restored.desc, '');
      expect(restored.code, '');
      expect(restored.enabled, false);
    });
  });
}
