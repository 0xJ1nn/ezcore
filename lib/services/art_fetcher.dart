import 'dart:async';
import 'dart:io';

import 'cover_art.dart' show coverRevision;
import 'game_art.dart';

/// Outcome of an explicit art lookup. Callers may ignore it; nothing is shown
/// to the user on failure.
enum ArtFetchOutcome {
  /// The opt-in setting is off — no request was made.
  disabled,

  /// A valid image was written to the local cache.
  saved,

  /// The lookup failed for any reason and was silently ignored.
  failed,
}

/// Libretro playlist folder names for common systems. Unknown systems fall
/// back to their own id so an explicit lookup is still attempted.
const Map<String, String> _thumbnailFolders = {
  'nes': 'Nintendo - Nintendo Entertainment System',
  'snes': 'Nintendo - Super Nintendo Entertainment System',
  'gb': 'Nintendo - Game Boy',
  'gbc': 'Nintendo - Game Boy Color',
  'gba': 'Nintendo - Game Boy Advance',
  'nds': 'Nintendo - Nintendo DS',
  'n64': 'Nintendo - Nintendo 64',
  'gc': 'Nintendo - GameCube',
  'wii': 'Nintendo - Wii',
  'psx': 'Sony - PlayStation',
  'ps2': 'Sony - PlayStation 2',
  'psp': 'Sony - PlayStation Portable',
  'genesis': 'Sega - Mega Drive - Genesis',
  'sms': 'Sega - Master System - Mark III',
  'dc': 'Sega - Dreamcast',
  'saturn': 'Sega - Sega Saturn',
  'arcade': 'Arcade',
};

/// Builds the Libretro thumbnail URL for [request]. Overridable in tests.
Uri defaultThumbnailUri(GameArtRequest request) {
  final folder = _thumbnailFolders[request.system.toLowerCase()] ??
      request.system;
  final title = normaliseArtTitle(request.title);
  return Uri.https('thumbnails.libretro.com', <String>[
    '',
    folder,
    'Named_Boxarts',
    '$title.png',
  ].join('/'));
}

/// Fetches [uri] and returns its bytes, enforcing a hard [deadline] and a
/// [maxBytes] cap. Overridable in tests.
typedef ArtBytesFetcher = Future<List<int>> Function(
  Uri uri,
  Duration deadline,
  int maxBytes,
);

/// Default [ArtBytesFetcher] using the platform HTTP client.
Future<List<int>> _httpFetch(
  Uri uri,
  Duration deadline,
  int maxBytes,
) async {
  final client = HttpClient()..connectionTimeout = deadline;
  try {
    final req = await client.getUrl(uri).timeout(deadline);
    final response = await req.close().timeout(deadline);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw StateError('HTTP ${response.statusCode}');
    }
    final chunks = <List<int>>[];
    var total = 0;
    await for (final chunk in response.timeout(deadline)) {
      total += chunk.length;
      if (total > maxBytes) throw StateError('Art response too large');
      chunks.add(chunk);
    }
    return chunks.expand((c) => c).toList();
  } finally {
    client.close();
  }
}

/// Fetches box art for a single library game into the local-only cache.
///
/// This lookup is **strictly opt-in**: it never runs unless the user has
/// enabled the art-lookup setting, and the resolver itself never touches the
/// network. The only datum sent is the game's name (and its system folder) as
/// the request path — no file paths, hashes, identifiers or analytics leave
/// the device, and the request is not logged or retried.
///
/// The Libretro thumbnail library is credited for the artwork: it is freely
/// available but is **not** public domain, and the images originate with each
/// game's developers, publishers and the project's contributors. ezCORE
/// neither owns nor redistributes it. A fetched image is written only to the
/// user's own cache under the local data directory, is never bundled,
/// uploaded or shared, and the user can purge it at any time. If anything
/// fails — setting off, timeout, limit exceeded, bad bytes, no network — the
/// lookup gives up silently and the procedural cover is shown instead.
Future<ArtFetchOutcome> fetchArtFor(
  GameArtRequest request, {
  GameArtResolver? resolver,
  ArtBytesFetcher? fetchBytes,
  Uri Function(GameArtRequest)? uriFor,
  Duration? timeout,
  int? maxBytes,
}) async {
  final art = resolver ?? GameArtResolver.shared;
  if (!art.lookupEnabled) return ArtFetchOutcome.disabled;

  final limit = maxBytes ?? 4 * 1024 * 1024;
  final deadline = timeout ?? const Duration(seconds: 6);
  final uri = (uriFor ?? defaultThumbnailUri)(request);
  if (!uri.hasScheme) return ArtFetchOutcome.failed;

  try {
    final bytes = await (fetchBytes ?? _httpFetch)(uri, deadline, limit);
    if (bytes.isEmpty || !isImageBytes(bytes)) return ArtFetchOutcome.failed;

    final target = File(art.cachePath(request));
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    coverRevision.value++;
    return ArtFetchOutcome.saved;
  } catch (_) {
    return ArtFetchOutcome.failed;
  }
}
