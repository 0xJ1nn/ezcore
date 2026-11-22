import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../state/save_sync.dart';
import '../version.dart' as version;

/// Called when the durable copy could not be written or read. The save itself
/// still succeeds against the primary, but the app must not keep claiming the
/// backup is healthy when it is not.
typedef MirrorFailureReporter = void Function(String reason);

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
    this.deviceId = '',
    this.deleted = false,
  });

  final String gameId;
  final String slot;
  final int size;
  final DateTime modified;
  final String appVersion;

  /// Which install wrote this entry. A shared backup folder can be used by
  /// more than one device, so tombstones are scoped to one install and never
  /// hide another device's save.
  final String deviceId;

  /// A deliberate delete. The mirror file is kept, but a tombstoned slot is
  /// never listed or restored, so a deleted save cannot come back later.
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'gameId': gameId,
    'slot': slot,
    'size': size,
    'modified': modified.toIso8601String(),
    'appVersion': appVersion,
    if (deviceId.isNotEmpty) 'deviceId': deviceId,
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
      deviceId: json['deviceId'] as String? ?? '',
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
///   save into a failure. It is reported through [onMirrorFailure] instead.
/// * Every upload also writes `<mirror>/saves/<gameId>/<slot>.bin` and an
///   index entry with the slot's size, modification time and app version.
/// * [list] is the union of primary and mirror. When both hold a slot the
///   primary wins, so the copy the player just saved is the one they see.
/// * Only slots recorded in the index are treated as saves. Unrelated files
///   somebody else put in the chosen folder are ignored.
/// * Deleting a save tombstones this install's index entry. The mirror bytes
///   are left alone, and another device's live entry for the same slot stays
///   live.
class MirroredSaveSyncProvider implements SaveSyncProvider {
  MirroredSaveSyncProvider(
    this.primary,
    this.mirrorRoot, {
    this.appVersion = version.appVersion,
    this.deviceId = '',
    this.onMirrorFailure,
  }) : _mirrorEstablished =
           _indexFileFor(mirrorRoot).existsSync() ||
           Directory('${mirrorRoot.path}/$_savesDir').existsSync();

  /// The save provider the app was already using (local vault in production).
  final SaveSyncProvider primary;

  /// Root of the durable backup folder, resolved before this wrapper exists.
  final Directory mirrorRoot;

  /// Written into each index entry so a future version can tell old saves.
  final String appVersion;

  /// Identifies this install in a backup folder that may be shared by two
  /// devices. Empty in sessions without a persisted install id.
  final String deviceId;

  /// Notified when the durable copy fails, so Settings can stop claiming the
  /// folder is working. Never allowed to fail the primary save.
  final MirrorFailureReporter? onMirrorFailure;

  /// Set once this folder has held a mirror. A folder that vanishes after
  /// that point is a real failure, not a fresh folder to create silently.
  bool _mirrorEstablished;

  /// Created lazily: a future constructed at widget-test setup time can
  /// belong to a paused fake-async zone and never schedule its callbacks.
  Future<void>? _mirrorQueue;

  /// Keeps the underlying provider's identity. The vault screen uses [id] to
  /// label the save list, and the primary is still the same local vault.
  @override
  String get id => primary.id;

  static const _savesDir = 'saves';
  static const _indexName = 'index.json';

  static File _indexFileFor(Directory root) =>
      File('${root.path}/$_savesDir/$_indexName');

  Directory get _mirrorSaves => Directory('${mirrorRoot.path}/$_savesDir');

  File get _indexFile => _indexFileFor(mirrorRoot);

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
    if (!await _hasLiveEntry(gameId, slot)) return null;
    try {
      final file = _mirrorFile(gameId, slot);
      if (file.existsSync()) return await file.readAsBytes();
    } catch (_) {
      _report(
        'The backup folder could not be read. Saves there are unavailable.',
      );
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
        // Re-stamp the restored save with this install's id so a later delete
        // on this device really tombstones it.
        await _mirrorUpload(ref.gameId, ref.slot, bytes);
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

  /// The index is the list of saves this app owns in the folder. Files that
  /// happen to sit in the same folder belong to their owners and are ignored.
  Future<List<String>> _mirrorGames(String? gameId) async {
    if (gameId != null) return [gameId];
    final games = <String>{};
    for (final entry in await _readIndex()) {
      if (entry.gameId.isNotEmpty) games.add(entry.gameId);
    }
    return games.toList();
  }

  /// Mirror slots backed by a live index entry, with metadata from the bytes
  /// on disk. A slot stays live while any device has a non-deleted entry.
  Future<List<SaveSlot>> _mirrorSlots(String gameId) async {
    final live = <String>{};
    for (final entry in await _readIndex()) {
      if (entry.gameId == gameId && entry.slot.isNotEmpty && !entry.deleted) {
        live.add(entry.slot);
      }
    }
    final out = <SaveSlot>[];
    for (final slot in live) {
      try {
        final file = _mirrorFile(gameId, slot);
        if (!file.existsSync()) continue;
        final stat = file.statSync();
        out.add(SaveSlot(id: slot, modified: stat.modified, size: stat.size));
      } catch (_) {}
    }
    return out;
  }

  Future<bool> _hasLiveEntry(String gameId, String slot) async {
    final entries = await _readIndex();
    return entries.any(
      (entry) => entry.gameId == gameId && entry.slot == slot && !entry.deleted,
    );
  }

  /// A folder that held saves and is now gone must not be silently recreated
  /// as an empty "working" backup.
  String? _mirrorBlockReason() {
    if (_mirrorEstablished && !mirrorRoot.existsSync()) {
      return 'The backup folder is no longer on this device. Choose a folder '
          'again to resume backups.';
    }
    return null;
  }

  Future<void> _mirrorUpload(
    String gameId,
    String slot,
    Uint8List bytes,
  ) async {
    final blocked = _mirrorBlockReason();
    if (blocked != null) {
      _report(blocked);
      return;
    }
    await _serialize(() async {
      try {
        final file = _mirrorFile(gameId, slot);
        file.parent.createSync(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        final modified = file.statSync().modified;
        final entries = await _readIndex();
        entries.removeWhere(
          (entry) =>
              entry.gameId == gameId &&
              entry.slot == slot &&
              entry.deviceId == deviceId,
        );
        entries.add(
          _IndexEntry(
            gameId: gameId,
            slot: slot,
            size: bytes.length,
            modified: modified,
            appVersion: appVersion,
            deviceId: deviceId,
          ),
        );
        if (!await _writeIndex(entries)) {
          _report(
            'The backup folder could not record this save. Check that it '
            'is writable.',
          );
          return;
        }
        _mirrorEstablished = true;
      } catch (_) {
        _report(
          'Saves could not be written to the backup folder. Check that '
          'it is writable.',
        );
      }
    });
  }

  /// Records a tombstone without touching the mirror bytes. Only this
  /// install's entry is tombstoned: deleting a local-only save on one device
  /// must never erase a save another device mirrored to the same folder.
  Future<void> _tombstone(String gameId, String slot) async {
    final blocked = _mirrorBlockReason();
    if (blocked != null) {
      _report(blocked);
      return;
    }
    await _serialize(() async {
      try {
        final entries = await _readIndex();
        final owned = entries.where(
          (entry) =>
              entry.gameId == gameId &&
              entry.slot == slot &&
              entry.deviceId == deviceId,
        );
        if (!owned.any((entry) => !entry.deleted)) return;
        final next = [
          for (final entry in entries)
            if (!(entry.gameId == gameId &&
                entry.slot == slot &&
                entry.deviceId == deviceId))
              entry,
          _IndexEntry(
            gameId: gameId,
            slot: slot,
            size: 0,
            modified: DateTime.now(),
            appVersion: appVersion,
            deviceId: deviceId,
            deleted: true,
          ),
        ];
        if (!await _writeIndex(next)) {
          _report(
            'The backup folder could not record the deleted save. Check '
            'that it is writable.',
          );
        }
      } catch (_) {
        _report(
          'The backup folder could not record the deleted save. Check '
          'that it is writable.',
        );
      }
    });
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

  /// Atomic so a concurrent read never sees a half-written index.
  Future<bool> _writeIndex(List<_IndexEntry> entries) async {
    try {
      final dir = _mirrorSaves;
      if (!dir.existsSync()) await dir.create(recursive: true);
      final tmp = File('${_indexFile.path}.tmp');
      await tmp.writeAsString(
        json.encode(entries.map((entry) => entry.toJson()).toList()),
        flush: true,
      );
      await tmp.rename(_indexFile.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Serializes index read/modify/write cycles so two quick saves cannot
  /// overwrite each other's entries.
  Future<void> _serialize(Future<void> Function() operation) {
    final previous = _mirrorQueue;
    final result = previous == null
        ? operation()
        : previous.then((_) => operation());
    _mirrorQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _report(String reason) {
    try {
      onMirrorFailure?.call(reason);
    } catch (_) {
      // Reporting must never fail the save that triggered it.
    }
  }
}
