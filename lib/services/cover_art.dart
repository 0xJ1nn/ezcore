import 'dart:io';

import 'package:flutter/painting.dart';

import 'package:flutter/foundation.dart';

import '../services/local_data_dir.dart';
import 'game_art.dart' show artExtensions, isImageBytes;

/// Deterministic per-game cover identity + screenshot-cover resolution.
///
/// No game art ships with the app, so every imported dump gets a stable,
/// generated cover (palette + motif derived from its id hash) inside the
/// approved black/blue/silver identity. When the player saves a screenshot,
/// a copy is pinned as the game's cover (`art/<gameId>.png`) and takes
/// precedence — covers become real captures of your own play.
class CoverSpec {
  const CoverSpec({
    required this.top,
    required this.bottom,
    required this.motif,
    required this.accent,
  });
  final int top;
  final int bottom;
  final int motif;
  final int accent;
}

const _palettes = [
  (0xFF16233A, 0xFF0A0A0A),
  (0xFF1B2B4A, 0xFF101820),
  (0xFF232B36, 0xFF12151B),
  (0xFF0E2A52, 0xFF0A0A0A),
  (0xFF2A3542, 0xFF141922),
  (0xFF1A2433, 0xFF0C0E12),
];

/// FNV-1a 32-bit hash (stable across runs and platforms).
int coverHash(String input) {
  var h = 0x811C9DC5;
  for (var i = 0; i < input.length; i++) {
    h ^= input.codeUnitAt(i);
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// Deterministic cover spec for [gameId]: palette pair, motif 0-4, and a
/// per-game accent drawn from the approved blues/whites.
CoverSpec coverSpecFor(String gameId) {
  final h = coverHash(gameId);
  final pal = _palettes[h % _palettes.length];
  const accents = [0xFF007BFF, 0xFF4DA3FF, 0xFFDDE6F4, 0xFFA8CEFF];
  return CoverSpec(
    top: pal.$1,
    bottom: pal.$2,
    motif: (h >> 8) % 5,
    accent: accents[(h >> 16) % accents.length],
  );
}

final Map<String, File?> _coverFileCache = <String, File?>{};

/// Rebuilds mounted covers after a screenshot replaces a pinned file.
final ValueNotifier<int> coverRevision = ValueNotifier<int>(0);

/// Local screenshot-cover file for [gameId], or null when none was pinned.
///
/// The first lookup checks disk. Repeated carousel frames reuse that result so
/// a drag does not perform synchronous filesystem probes for every cover.
/// Screenshot writes call [invalidateCoverFile] to publish the new file.
File? coverFileFor(String gameId) {
  if (_coverFileCache.containsKey(gameId)) {
    return _coverFileCache[gameId];
  }
  final file = File('${PlatformLocalDataDirProvider.path()}/art/$gameId.png');
  final resolved = file.existsSync() ? file : null;
  _coverFileCache[gameId] = resolved;
  return resolved;
}

void invalidateCoverFile(String gameId) {
  // Drop the decoded image once, here, where the file changes. (Evicting in
  // the cover's build reloaded every cover from disk on every carousel frame.)
  // A chosen cover may be any supported container, so evict every path the
  // resolver could have used, not just the screenshot writer's .png.
  final old =
      _coverFileCache.remove(gameId) ??
      File('${PlatformLocalDataDirProvider.path()}/art/$gameId.png');
  PaintingBinding.instance.imageCache.evict(FileImage(old));
  for (final ext in artExtensions) {
    if (ext == '.png') continue;
    PaintingBinding.instance.imageCache.evict(
      FileImage(
        File('${PlatformLocalDataDirProvider.path()}/art/$gameId$ext'),
      ),
    );
  }
  coverRevision.value++;
}

/// Copies a cover the person chose into the pinned slot for [gameId].
///
/// The file keeps its own container under the name the screenshot writer
/// already uses, so a pick, a capture and a fetched thumbnail all land in the
/// same place. Anything unreadable, or not a complete supported image, leaves
/// the current cover alone and returns null instead of throwing.
Future<File?> setCoverFromFile(String gameId, String sourcePath) async {
  final source = File(sourcePath);
  late final List<int> bytes;
  try {
    bytes = await source.readAsBytes();
  } catch (_) {
    return null;
  }
  if (!isImageBytes(bytes)) return null;

  final lower = sourcePath.toLowerCase();
  var ext = artExtensions.first;
  for (final candidate in artExtensions) {
    if (lower.endsWith(candidate)) {
      ext = candidate;
      break;
    }
  }

  try {
    final folder = await Directory(
      '${PlatformLocalDataDirProvider.path()}/art',
    ).create(recursive: true);
    // One cover per game: an earlier pick in any container is removed, so a
    // .jpg replaced by a .png never leaves two files competing on disk.
    for (final old in artExtensions) {
      final stale = File('${folder.path}/$gameId$old');
      if (stale.existsSync()) await stale.delete();
    }
    final written = File('${folder.path}/$gameId$ext');
    await written.writeAsBytes(bytes, flush: true);
    invalidateCoverFile(gameId);
    return written;
  } catch (_) {
    return null;
  }
}

/// Returns [gameId] to its generated cover by removing any pinned file.
///
/// Only this game's art is deleted; every other game keeps its own cover.
Future<void> resetCover(String gameId) async {
  final folder = Directory('${PlatformLocalDataDirProvider.path()}/art');
  if (folder.existsSync()) {
    for (final ext in artExtensions) {
      final file = File('${folder.path}/$gameId$ext');
      if (!file.existsSync()) continue;
      try {
        file.deleteSync();
      } catch (_) {
        // A file locked by the OS stays, but the revision still bumps so a
        // tile re-resolves rather than holding a stale image.
      }
    }
  }
  invalidateCoverFile(gameId);
}

/// Whether [gameId] has a pinned cover in any of the supported containers.
///
/// Used to offer a reset only when there is something to undo.
bool hasPinnedCover(String gameId) {
  final folder = Directory('${PlatformLocalDataDirProvider.path()}/art');
  if (!folder.existsSync()) return false;
  for (final ext in artExtensions) {
    if (File('${folder.path}/$gameId$ext').existsSync()) return true;
  }
  return false;
}
