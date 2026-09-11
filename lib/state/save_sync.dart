import 'dart:io';
import 'dart:typed_data';

/// Save/sync seam. The runtime produces opaque state bytes; providers move
/// them. Local vault today — iCloud / OneDrive / account sync plug in here
/// tomorrow without touching cores, the player, or the library.
abstract class SaveSyncProvider {
  String get id;

  Future<List<SaveSlot>> list(String gameId);
  Future<Uint8List?> download(String gameId, String slot);
  Future<void> upload(String gameId, String slot, Uint8List bytes);
  Future<void> remove(String gameId, String slot);
}

class SaveSlot {
  const SaveSlot({
    required this.id,
    required this.modified,
    required this.size,
  });

  final String id;
  final DateTime modified;
  final int size;
}

/// Ephemeral default: in-memory map. Tests and sessions without storage.
class MemorySaveSyncProvider implements SaveSyncProvider {
  @override
  String get id => 'memory';

  final Map<String, Map<String, _Entry>> _vault = {};

  @override
  Future<List<SaveSlot>> list(String gameId) async {
    final games = _vault[gameId] ?? {};
    return games.entries
        .map((e) => SaveSlot(
              id: e.key,
              modified: e.value.modified,
              size: e.value.bytes.length,
            ))
        .toList();
  }

  @override
  Future<Uint8List?> download(String gameId, String slot) async =>
      _vault[gameId]?[slot]?.bytes;

  @override
  Future<void> upload(String gameId, String slot, Uint8List bytes) async {
    _vault.putIfAbsent(gameId, () => {})[slot] =
        _Entry(bytes, DateTime.now());
  }

  @override
  Future<void> remove(String gameId, String slot) async {
    _vault[gameId]?.remove(slot);
  }
}

class _Entry {
  _Entry(this.bytes, this.modified);
  final Uint8List bytes;
  final DateTime modified;
}

/// On-disk vault: `<root>/<gameId>/<slot>.bin`. No cloud, no account,
/// no network — the baseline every future provider must beat.
class LocalSaveSyncProvider implements SaveSyncProvider {
  LocalSaveSyncProvider(this.root);
  final Directory root;

  @override
  String get id => 'local';

  File _file(String gameId, String slot) =>
      File('${root.path}/$gameId/$slot.bin');

  @override
  Future<List<SaveSlot>> list(String gameId) async {
    final dir = Directory('${root.path}/$gameId');
    if (!dir.existsSync()) return [];
    final out = <SaveSlot>[];
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.bin')) {
        final stat = entity.statSync();
        out.add(SaveSlot(
          id: entity.uri.pathSegments.last.replaceAll('.bin', ''),
          modified: stat.modified,
          size: stat.size,
        ));
      }
    }
    return out;
  }

  @override
  Future<Uint8List?> download(String gameId, String slot) async {
    final file = _file(gameId, slot);
    if (!file.existsSync()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> upload(String gameId, String slot, Uint8List bytes) async {
    final file = _file(gameId, slot);
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> remove(String gameId, String slot) async {
    final file = _file(gameId, slot);
    if (file.existsSync()) await file.delete();
  }
}
