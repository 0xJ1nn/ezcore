import 'dart:io';

import 'package:flutter/foundation.dart';

import '../services/local_data_dir.dart';

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
  _coverFileCache.remove(gameId);
  coverRevision.value++;
}
