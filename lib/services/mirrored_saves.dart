// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../state/save_sync.dart';
import '../version.dart' as version;

/// One save entry in the mirror index. The index is a small JSON list at
/// `<mirror>/saves/index.json`; the bytes themselves live next to it in
/// `<mirror>/saves/<gameId>/<slot>.bin`.
class _IndexEntry {
  const _IndexEntry({
    required this.gameId,
    required this.slot,
    required this.size,
    required this.modified,
    required this.appVersion,
    this.deleted = false,
  });

  final String gameId;
  final String slot;
  final int size;
  final DateTime modified;
  final String appVersion;

  /// A deliberate delete. The mirror file is kept, but a tombstoned slot is
  /// never listed or restored, so a deleted save cannot come back later.
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'slot': slot,
    'size': size,
    'modified': modified.toIso8601String(),
    'appVersion': appVersion,
    if (deleted) 'deleted': true,
  };

  factory _IndexEntry.fromJson(Map<String, dynamic> json) {
    return _IndexEntry(
      gameId: json['gameId'] as String? ?? '',
      slot: json['slot'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      modified:
          DateTime.tryParse(json['modified'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appVersion: json['appVersion'] as String? ?? '',
      deleted: json['deleted'] == true,
    );
  }
}

/// A save that exists only in the backup folder. [gameId] and [slot] are
/// enough for a caller to offer a targeted restore.
class MirrorSaveRef {
  const MirrorSaveRef({
    required this.gameId,
    required this.slot,
    required this.size,
    required this.modified,
  });

  final String gameId;
  final String slot;
  final int size;
  final DateTime modified;
}

/// A [SaveSyncProvider] that keeps a survival copy of every save in a folder
/// which is expected to outlive the app (iCloud, OneDrive, a SAF tree, or a
/// durable device folder).
///
/// Semantics:
///
/// * [upload] and [remove] always talk to the [primary] first. Its result is
///   the result of the operation; a broken mirror never turns a successful
///   save into a failure and never surfaces a message to the player.
/// * Every upload also writes `<mirror>/saves/<gameId>/<slot>.bin` and an
///   index entry with the slot's size, modification time and app version.
/// * [list] is the union of primary and mirror. When both hold a slot the
///   primary wins, so the copy the player just saved is the one they see.
/// * Deleting a save removes it from the primary and records a tombstone in
///   the index. The mirror bytes are deliberately left alone — losing the
///   app must not erase the survival copy — but a tombstoned slot is never
///   listed, downloaded or restored again.
class MirroredSaveSyncProvider implements SaveSyncProvider {
  MirroredSaveSyncProvider(
    this.primary,
    this.mirrorRoot, {
    this.appVersion = version.appVersion,
  });

  /// The save provider the app was already using (local vault in production).
  final SaveSyncProvider primary;

  /// Root of the durable backup folder, resolved before this wrapper exists.
  final Directory mirrorRoot;

  /// Written into each index entry so a future version can tell old saves.
  final String appVersion;

  /// Keep the underlying provider's identity. The vault screen uses [id] to
  /// label the save list, and the primary is still the same local vault.
  @override
  String get id => primary.id;

  static const _savesDir = 'saves';
  static const _indexName = 'index.json';

  Directory get _mirrorSaves => Directory('${mirrorRoot.path}/$_savesDir');

  File get _indexFile => File('${_mirrorSaves.path}/$_indexName');

  File _mirrorFile(String gameId, String slot) =>
      File('${_mirrorSaves.path}/$gameId/$slot.bin');

  @override
  Future<List<SaveSlot>> list(String gameId) async {
    final fromPrimary = await primary.list(gameId);
    final primaryIds = fromPrimary.map((slot) => slot.id).toSet();
    final out = <SaveSlot>[...fromPrimary];
    for (final slot in await _mirrorSlots(gameId)) {
      if (!primaryIds.contains(slot.id)) out.add(slot);
    }
    return out;
  }

  @override
  Future<Uint8List?> download(String gameId, String slot) async {
    final bytes = await primary.download(gameId, slot);
    if (bytes != null) return bytes;
    if (await _isTombstoned(gameId, slot)) return null;
    try {
      final file = _mirrorFile(gameId, slot);
      if (file.existsSync()) return await file.readAsBytes();
    } catch (_) {
      // A mirror that cannot be read is simply not available.
    }
    return null;
  }

  @override
  Future<void> upload(String gameId, String slot, Uint8List bytes) async {
    // The primary is authoritative: its result is the caller's result.
    await primary.upload(gameId, slot, bytes);
    await _mirrorUpload(gameId, slot, bytes);
  }

  @override
  Future<void> remove(String gameId, String slot) async {
    await primary.remove(gameId, slot);
    await _tombstone(gameId, slot);
  }

  /// Copies every mirror-only save into the primary. Returns how many were
  /// copied. Tombstoned slots are skipped so a deliberate delete stays deleted.
  Future<int> restoreFromMirror() async {
    final pending = await mirrorOnlySlots();
    var restored = 0;
    for (final ref in pending) {
      try {
        final file = _mirrorFile(ref.gameId, ref.slot);
        if (!file.existsSync()) continue;
        final bytes = await file.readAsBytes();
        await primary.upload(ref.gameId, ref.slot, bytes);
        restored++;
      } catch (_) {
        // One damaged save must not stop the rest of the restore.
      }
    }
    return restored;
  }

  /// Slots that exist in the mirror but not in the primary, across every game
  /// (or just [gameId] when supplied). Tombstoned slots are excluded. These
  /// are the saves a restore can offer.
  Future<List<MirrorSaveRef>> mirrorOnlySlots({String? gameId}) async {
    final games = await _mirrorGames(gameId);
    final out = <MirrorSaveRef>[];
    for (final game in games) {
      final primaryIds = (await primary.list(game)).map((s) => s.id).toSet();
      for (final slot in await _mirrorSlots(game)) {
        if (primaryIds.contains(slot.id)) continue;
        out.add(
          MirrorSaveRef(
            gameId: game,
            slot: slot.id,
            size: slot.size,
            modified: slot.modified,
          ),
        );
      }
    }
    return out;
  }

  Future<List<String>> _mirrorGames(String? gameId) async {
    if (gameId != null) return [gameId];
    final games = <String>{};
    try {
      final dir = _mirrorSaves;
      if (dir.existsSync()) {
        for (final entity in dir.listSync()) {
          if (entity is Directory) {
            games.add(entity.uri.pathSegments.last);
          }
        }
      }
    } catch (_) {}
    for (final entry in await _readIndex()) {
      if (entry.gameId.isNotEmpty) games.add(entry.gameId);
    }
    return games.toList();
  }

  /// Mirror slots for one game, with metadata from the actual bytes on disk.
  /// Tombstones remove a slot from this view without deleting its file.
  Future<List<SaveSlot>> _mirrorSlots(String gameId) async {
    final dir = Directory('${_mirrorSaves.path}/$gameId');
    if (!dir.existsSync()) return const [];
    final deleted = (await _readIndex())
        .where((entry) => entry.gameId == gameId && entry.deleted)
        .map((entry) => entry.slot)
        .toSet();
    final out = <SaveSlot>[];
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.bin')) continue;
        final slot = entity.uri.pathSegments.last.replaceAll('.bin', '');
        if (deleted.contains(slot)) continue;
        final stat = entity.statSync();
        out.add(SaveSlot(id: slot, modified: stat.modified, size: stat.size));
      }
    } catch (_) {}
    return out;
  }

  Future<bool> _isTombstoned(String gameId, String slot) async {
    try {
      return (await _readIndex()).any(
        (entry) =>
            entry.gameId == gameId && entry.slot == slot && entry.deleted,
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _mirrorUpload(
    String gameId,
    String slot,
    Uint8List bytes,
  ) async {
    try {
      final file = _mirrorFile(gameId, slot);
      file.parent.createSync(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      final modified = file.statSync().modified;
      final entries = await _readIndex();
      entries.removeWhere(
        (entry) => entry.gameId == gameId && entry.slot == slot,
      );
      entries.add(
        _IndexEntry(
          gameId: gameId,
          slot: slot,
          size: bytes.length,
          modified: modified,
          appVersion: appVersion,
        ),
      );
      await _writeIndex(entries);
    } catch (_) {
      // Mirroring is best-effort. The primary save has already succeeded and
      // stays the single result the caller sees.
    }
  }

  /// Records a tombstone without touching the mirror bytes.
  Future<void> _tombstone(String gameId, String slot) async {
    try {
      final entries = await _readIndex();
      entries.removeWhere(
        (entry) => entry.gameId == gameId && entry.slot == slot,
      );
      entries.add(
        _IndexEntry(
          gameId: gameId,
          slot: slot,
          size: 0,
          modified: DateTime.now(),
          appVersion: appVersion,
          deleted: true,
        ),
      );
      await _writeIndex(entries);
    } catch (_) {}
  }

  Future<List<_IndexEntry>> _readIndex() async {
    try {
      final file = _indexFile;
      if (!file.existsSync()) return [];
      final decoded = json.decode(await file.readAsString());
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map<String, dynamic>) _IndexEntry.fromJson(item),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(List<_IndexEntry> entries) async {
    try {
      final dir = _mirrorSaves;
      if (!dir.existsSync()) await dir.create(recursive: true);
      await _indexFile.writeAsString(
        json.encode(entries.map((entry) => entry.toJson()).toList()),
        flush: true,
      );
    } catch (_) {
      // A failed index write must never fail the save that caused it.
    }
  }
}
