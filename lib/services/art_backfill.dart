// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import '../models/game_entry.dart';
import 'art_fetcher.dart';
import 'game_art.dart';

/// Outcome of one backfill run.
class ArtBackfillResult {
  const ArtBackfillResult({required this.saved, required this.attempted});

  /// How many images were written to the local cache.
  final int saved;

  /// How many lookups were made, including failed ones.
  final int attempted;

  bool get ran => attempted > 0;
}

/// Games in [games] whose art has to be looked up: a game with a real
/// identity whose local sources all miss.
List<GameArtRequest> missingArtRequests(
  List<GameEntry> games, {
  GameArtResolver? resolver,
}) {
  final art = resolver ?? GameArtResolver.shared;
  final out = <GameArtRequest>[];
  final seen = <String>{};
  for (final game in games) {
    if (game.id.isEmpty || game.title.trim().isEmpty) continue;
    final request = GameArtRequest(
      id: game.id,
      title: game.title,
      system: game.system,
    );
    final key = '${request.system}\u0000${normaliseArtTitle(request.title)}';
    if (!seen.add(key)) continue;
    if (art.resolve(request) != null) continue;
    out.add(request);
  }
  return out;
}

/// Looks up art for every game that has none, one request at a time.
///
/// This is the only path from a library to the network for art, and it runs
/// only when the player asks for it and the lookup setting is on. It stops
/// after [maxFailures] consecutive failures so a missing network does not
/// turn into a long spinner, and never throws: a failed lookup leaves the
/// generated cover in place.
Future<ArtBackfillResult> backfillMissingArt(
  List<GameEntry> games, {
  GameArtResolver? resolver,
  ArtBytesFetcher? fetchBytes,
  int maxFailures = 3,
  int limit = 60,
}) async {
  final art = resolver ?? GameArtResolver.shared;
  if (!art.lookupEnabled) {
    return const ArtBackfillResult(saved: 0, attempted: 0);
  }
  final requests = missingArtRequests(games, resolver: art).take(limit);

  var saved = 0;
  var attempted = 0;
  var failures = 0;
  for (final request in requests) {
    if (failures >= maxFailures) break;
    attempted++;
    final outcome = await fetchArtFor(
      request,
      resolver: art,
      fetchBytes: fetchBytes,
    );
    if (outcome == ArtFetchOutcome.saved) {
      saved++;
      failures = 0;
    } else if (outcome == ArtFetchOutcome.failed) {
      failures++;
    } else {
      break; // the setting was turned off mid-run
    }
  }
  return ArtBackfillResult(saved: saved, attempted: attempted);
}

/// True when the folder at [path] holds at least one readable image file.
///
/// Used by Settings to tell the player that a folder they picked is real
/// before it is saved, instead of letting every tile silently ignore it.
bool artFolderHasImages(String path) {
  final root = Directory(path);
  if (!root.existsSync()) return false;
  final pending = <Directory>[root];
  var visited = 0;
  while (pending.isNotEmpty && visited < 400) {
    final dir = pending.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final entry in entries) {
      visited++;
      if (entry is Directory) {
        pending.add(entry);
        continue;
      }
      final name = entry.path.split(Platform.pathSeparator).last;
      final dot = name.lastIndexOf('.');
      if (dot <= 0) continue;
      if (artExtensions.contains(name.substring(dot).toLowerCase())) {
        return true;
      }
    }
  }
  return false;
}
