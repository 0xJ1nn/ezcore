import 'dart:convert';
import 'dart:io';

import 'cover_art.dart' show coverFileFor, coverRevision;
import 'local_data_dir.dart';

/// Persisted preference keys read by art resolution.
const String artFolderKey = 'artFolder';
const String artLookupKey = 'artLookup';

/// Extensions accepted for locally supplied art, in lookup order.
const List<String> artExtensions = ['.png', '.jpg', '.jpeg', '.webp'];

/// The identity of a library game, as needed to find its art.
///
/// [id] is the stable library id; [title] is the game's own title (not a
/// display-wrapped one) and [system] is its system folder/id. No file path,
/// hash or any other datum leaves the device during resolution.
///
/// [contentPresent] records what the caller already knows about the entry's
/// file. A game whose file is gone keeps its generated cover; an entry kept
/// because its folder is unplugged is still reported as present.
class GameArtRequest {
  const GameArtRequest({
    required this.id,
    required this.title,
    required this.system,
    this.contentPresent = true,
  });

  final String id;
  final String title;
  final String system;
  final bool contentPresent;

  @override
  bool operator ==(Object other) =>
      other is GameArtRequest &&
      other.id == id &&
      other.title == title &&
      other.system == system &&
      other.contentPresent == contentPresent;

  @override
  int get hashCode => Object.hash(id, title, system, contentPresent);
}

/// Normalises a ROM title for case-insensitive art matching.
///
/// Lower-cases, drops a trailing region tag such as `(USA)` or `[Europe]`,
/// strips a file extension, and folds `:`/`_`/`-`/whitespace to one space so
/// `Lanterns_of_Vell(USA).zip` and `Lanterns - of Vell.png` agree.
String normaliseArtTitle(String title) {
  var s = title.trim().toLowerCase();
  // A single trailing file extension: a dot after the last space, at most
  // a few characters long (never eat a dot inside the title).
  final dot = s.lastIndexOf('.');
  if (dot > s.lastIndexOf(RegExp(r'\s')) && s.length - dot <= 6) {
    s = s.substring(0, dot);
  }
  // A trailing parenthesised/bracketed region or revision tag.
  for (var i = 0; i < 3; i++) {
    final trimmed = s.replaceFirst(RegExp(r'\s*[(\[][^)\]]*[)\]]\s*$'), '');
    if (trimmed == s) break;
    s = trimmed;
  }
  return s.replaceAll(RegExp(r'[:_\-\.\s]+'), ' ').trim();
}

/// A pure-Dart SHA-1 digest of [input], as lowercase hex.
///
/// Used only to name locally cached art so a title never appears as a
/// readable filename. Kept dependency-free to match the hashing services.
String sha1Hex(String input) {
  final bytes = utf8.encode(input);
  final msg = <int>[...bytes, 0x80];
  while (msg.length % 64 != 56) {
    msg.add(0);
  }
  final bitLength = bytes.length * 8;
  for (var i = 7; i >= 0; i--) {
    msg.add((bitLength >> (i * 8)) & 0xFF);
  }

  var h0 = 0x67452301;
  var h1 = 0xEFCDAB89;
  var h2 = 0x98BADCFE;
  var h3 = 0x10325476;
  var h4 = 0xC3D2E1F0;
  final w = List<int>.filled(80, 0);

  int rotl(int x, int n) => ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF;

  for (var off = 0; off < msg.length; off += 64) {
    for (var i = 0; i < 16; i++) {
      final j = off + i * 4;
      w[i] = (msg[j] << 24) |
          (msg[j + 1] << 16) |
          (msg[j + 2] << 8) |
          msg[j + 3];
    }
    for (var i = 16; i < 80; i++) {
      w[i] = rotl(w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16], 1);
    }
    var a = h0;
    var b = h1;
    var c = h2;
    var d = h3;
    var e = h4;
    for (var i = 0; i < 80; i++) {
      final int f;
      final int k;
      if (i < 20) {
        f = (b & c) | (~b & d);
        k = 0x5A827999;
      } else if (i < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (i < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }
      final temp = (rotl(a, 5) + f + e + k + w[i]) & 0xFFFFFFFF;
      e = d;
      d = c;
      c = rotl(b, 30);
      b = a;
      a = temp;
    }
    h0 = (h0 + a) & 0xFFFFFFFF;
    h1 = (h1 + b) & 0xFFFFFFFF;
    h2 = (h2 + c) & 0xFFFFFFFF;
    h3 = (h3 + d) & 0xFFFFFFFF;
    h4 = (h4 + e) & 0xFFFFFFFF;
  }

  String word(int v) => v
      .toUnsigned(32)
      .toRadixString(16)
      .padLeft(8, '0');
  return word(h0) + word(h1) + word(h2) + word(h3) + word(h4);
}

/// Stable, opaque key for a game's cached art. Never contains the title.
String artCacheKey(GameArtRequest request) =>
    artCacheKeyFor(request.id, request.system, request.title);

/// The id separates two dumps that share a title and system; the title keeps
/// a re-scrape of the same game on its own cache entry.
String artCacheKeyFor(String id, String system, String title) => sha1Hex(
      '$id\u0000${system.toLowerCase()}\u0000${normaliseArtTitle(title)}',
    );

/// Checks whether [bytes] is a complete PNG, JPEG or WebP image rather than
/// a text file, an empty file or a truncated/corrupt image. Structural checks
/// on the container header and trailer catch the common bad cases without
/// needing an image codec or any platform channel.
bool isImageBytes(List<int> b) {
  if (b.length < 12 || b.length > 32 * 1024 * 1024) return false;
  final isPng = b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A;
  final isJpeg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
  final isWebp = b[0] == 0x52 &&
      b[1] == 0x49 &&
      b[2] == 0x46 &&
      b[3] == 0x46 &&
      b[8] == 0x57 &&
      b[9] == 0x45 &&
      b[10] == 0x42 &&
      b[11] == 0x50;
  if (isWebp) return true;
  if (!isPng && !isJpeg) return false;
  final n = b.length;
  if (isPng) {
    // A complete PNG ends with an IEND chunk: length 0, 'IEND', CRC.
    return b[n - 8] == 0x49 &&
        b[n - 7] == 0x45 &&
        b[n - 6] == 0x4E &&
        b[n - 5] == 0x44;
  }
  // A complete JPEG ends with the EOI marker.
  return b[n - 2] == 0xFF && b[n - 1] == 0xD9;
}

/// Checks that [file] is readable and really is a supported image, not just
/// a file with an image extension. Delegates to [isImageBytes] so local and
/// fetched art use exactly the same acceptance rule.
bool isDecodableImage(File file) {
  try {
    if (!file.existsSync()) return false;
    return isImageBytes(file.readAsBytesSync());
  } catch (_) {
    return false;
  }
}

/// Reads the two art settings out of the persisted settings map.
class GameArtSettings {
  const GameArtSettings({this.artFolder, this.artLookup = false});

  final String? artFolder;
  final bool artLookup;

  factory GameArtSettings.fromMap(Map<String, dynamic> settings) {
    final folder = settings[artFolderKey];
    final lookup = settings[artLookupKey];
    return GameArtSettings(
      artFolder: folder is String && folder.trim().isNotEmpty
          ? folder.trim()
          : null,
      artLookup: lookup is bool && lookup,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GameArtSettings &&
      other.artFolder == artFolder &&
      other.artLookup == artLookup;

  @override
  int get hashCode => Object.hash(artFolder, artLookup);
}

/// Validates a candidate file before it is allowed to reach a tile.
typedef ArtImageValidator = bool Function(File file);

/// Resolves a library game's art from local sources only, in strict order:
///
/// 1. a screenshot the player pinned under the local data `art/` folder,
/// 2. the user's media folder (`<artFolder>/<system>/<title>`),
/// 3. the opt-in, locally cached thumbnail when [GameArtSettings.artLookup]
///    is enabled.
///
/// A candidate must exist, be readable and pass [validator]; otherwise the
/// next source is tried and, if none qualifies, `null` is returned so the
/// procedural cover is shown. The resolver never performs network I/O —
/// fetching is an explicit, separate step in `art_fetcher.dart`.
class GameArtResolver {
  GameArtResolver({
    ArtImageValidator? validator,
    String? localDataPath,
    GameArtSettings? settings,
  })  : _validator = validator ?? isDecodableImage,
        _settings = settings ?? const GameArtSettings() {
    _localDataPath = localDataPath;
  }

  /// The app-wide instance, kept in sync with settings by the app root.
  static final GameArtResolver shared = GameArtResolver();

  final ArtImageValidator _validator;
  String? _localDataPath;
  GameArtSettings _settings;

  /// Whether third-party thumbnail lookup is currently allowed.
  bool get lookupEnabled => _settings.artLookup;

  /// Called by the app root and Settings whenever preferences change.
  void sync(Map<String, dynamic> settings) {
    final next = GameArtSettings.fromMap(settings);
    if (next == _settings) return;
    _settings = next;
    // Reuse the cover revision so mounted tiles rebuild with the new inputs.
    coverRevision.value++;
  }

  String get _dataPath => _localDataPath ?? PlatformLocalDataDirProvider.path();

  /// Path the fetcher writes a thumbnails response to for [request].
  String cachePath(GameArtRequest request) =>
      '$_dataPath/art-cache/${artCacheKey(request)}.img';

  /// Resolves [request] to an on-disk image, or null for the procedural cover.
  File? resolve(GameArtRequest request) {
    // No library identity: never show art for a placeholder or unknown game.
    if (request.id.isEmpty || request.title.trim().isEmpty) return null;
    // The entry's file is gone: its art no longer belongs to a tile. An
    // unplugged folder keeps its entries, and those still count as present.
    if (!request.contentPresent) return null;

    final pinned = _pinned(request.id);
    if (pinned != null) return pinned;

    final media = _fromMediaFolder(request);
    if (media != null) return media;

    if (_settings.artLookup) {
      final cached = File(cachePath(request));
      if (_validator(cached)) return cached;
    }
    return null;
  }

  File? _qualify(File file) => _validator(file) ? file : null;

  File? _pinned(String id) {
    // The existing screenshot writer pins a .png. coverFileFor keeps that
    // lookup cached and invalidated; the other extensions extend the same
    // convention without touching the writer.
    final png = coverFileFor(id);
    if (png != null) {
      final valid = _qualify(png);
      if (valid != null) return valid;
    }
    for (final ext in artExtensions) {
      if (ext == '.png') continue;
      final candidate = File('$_dataPath/art/$id$ext');
      final valid = _qualify(candidate);
      if (valid != null) return valid;
    }
    return null;
  }

  File? _fromMediaFolder(GameArtRequest request) {
    final folder = _settings.artFolder;
    if (folder == null) return null;
    final root = Directory(folder);
    if (!root.existsSync()) return null;

    final wantedSystem = request.system.trim().toLowerCase();
    final wantedTitle = normaliseArtTitle(request.title);
    if (wantedTitle.isEmpty) return null;

    Directory? systemDir;
    try {
      for (final entity in root.listSync(followLinks: false)) {
        if (entity is Directory &&
            entity.path.split(Platform.pathSeparator).last.toLowerCase() ==
                wantedSystem) {
          systemDir = entity;
          break;
        }
      }
    } catch (_) {
      return null;
    }
    if (systemDir == null) return null;

    try {
      for (final entity in systemDir.listSync(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        if (!artExtensions.contains(name.substring(dot).toLowerCase())) {
          continue;
        }
        if (normaliseArtTitle(name.substring(0, dot)) == wantedTitle) {
          final valid = _qualify(entity);
          if (valid != null) return valid;
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
