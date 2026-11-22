// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import '../services/sha256.dart';
import '../version.dart';

/// Where download builds look for the latest published release.
final Uri updateEndpoint = Uri.parse(
  'https://api.github.com/repos/0xJ1nn/ezcore/releases/latest',
);

/// Sent with every request so the service can identify the client.
const String updateUserAgent = 'ezCORE-updater';

/// Set by store builds with `--dart-define=EZ_STORE_BUILD=true`.
///
/// Store builds never use the update checker; they receive updates from their
/// store instead. Download builds leave the define unset.
const bool isStoreBuild = bool.fromEnvironment(
  'EZ_STORE_BUILD',
  defaultValue: false,
);

/// The platforms that receive download builds.
enum DownloadPlatform { windows, macos, linux }

/// The running platform, or null on platforms without a download build.
DownloadPlatform? currentDownloadPlatform() {
  if (Platform.isWindows) return DownloadPlatform.windows;
  if (Platform.isMacOS) return DownloadPlatform.macos;
  if (Platform.isLinux) return DownloadPlatform.linux;
  return null;
}

/// Compares two version strings numerically.
///
/// Returns a negative number when [a] is older than [b], zero when they are
/// equal and a positive number when [a] is newer. A leading "v" and any
/// pre-release or build suffix are ignored, so `v1.2.0` and `1.2.0` compare
/// equal. Missing components count as zero.
int compareVersions(String a, String b) {
  final left = _versionParts(a);
  final right = _versionParts(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}

List<int> _versionParts(String raw) {
  var text = raw.trim();
  if (text.startsWith('v') || text.startsWith('V')) {
    text = text.substring(1);
  }
  final suffix = text.indexOf(RegExp(r'[-+]'));
  if (suffix >= 0) text = text.substring(0, suffix);
  if (text.isEmpty) return const [0];
  return text.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}

/// A downloadable file attached to a release.
class UpdateAsset {
  const UpdateAsset({
    required this.name,
    required this.url,
    this.size,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) => UpdateAsset(
        name: (json['name'] as String?) ?? '',
        url: (json['browser_download_url'] as String?) ?? '',
        size: json['size'] is num ? (json['size'] as num).toInt() : null,
      );

  final String name;
  final String url;
  final int? size;
}

/// A published release, reduced to the fields the updater uses.
class UpdateRelease {
  const UpdateRelease({
    required this.tag,
    required this.body,
    required this.assets,
    this.draft = false,
    this.prerelease = false,
    this.pageUrl = '',
  });

  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final rawAssets = json['assets'];
    final assets = <UpdateAsset>[];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        if (item is Map<String, dynamic>) assets.add(UpdateAsset.fromJson(item));
      }
    }
    return UpdateRelease(
      tag: (json['tag_name'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      assets: assets,
      draft: json['draft'] == true,
      prerelease: json['prerelease'] == true,
      pageUrl: (json['html_url'] as String?) ?? '',
    );
  }

  final String tag;
  final String body;
  final List<UpdateAsset> assets;
  final bool draft;
  final bool prerelease;
  final String pageUrl;

  String? assetName(DownloadPlatform platform) =>
      pickAsset(assets, platform)?.name;
}

/// Chooses the best file for [platform].
///
/// The installer is preferred on Windows, the disk image on macOS and the
/// AppImage on Linux, with the portable archive as the fallback.
UpdateAsset? pickAsset(List<UpdateAsset> assets, DownloadPlatform platform) {
  const extensions = <DownloadPlatform, List<String>>{
    DownloadPlatform.windows: ['.exe', '.zip'],
    DownloadPlatform.macos: ['.dmg', '.zip'],
    DownloadPlatform.linux: ['.appimage', '.tar.gz'],
  };
  for (final extension in extensions[platform] ?? const <String>[]) {
    for (final asset in assets) {
      if (asset.name.toLowerCase().endsWith(extension)) return asset;
    }
  }
  return null;
}

/// Reads a SHA256SUMS.txt file into a name-to-digest map.
Map<String, String> parseChecksums(String text) {
  final sums = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+)$').firstMatch(trimmed);
    if (match == null) continue;
    sums[match.group(2)!.trim()] = match.group(1)!.toLowerCase();
  }
  return sums;
}

/// Returns true only when [bytes] hash to the digest published for [assetName].
///
/// A missing entry is a refusal, not an empty pass.
bool verifyChecksum(List<int> bytes, String sumsText, String assetName) {
  final expected = parseChecksums(sumsText)[assetName];
  if (expected == null) return false;
  return sha256Hex(bytes) == expected;
}

/// HTTP seam for update requests. A fake can be injected in tests.
abstract class UpdateHttpClient {
  Future<String> getText(
    Uri url, {
    String userAgent = updateUserAgent,
  });

  Future<List<int>> getBytes(
    Uri url, {
    String userAgent = updateUserAgent,
  });
}

/// Production client. Uses the platform HTTP stack, so no package is needed.
class IoUpdateHttpClient implements UpdateHttpClient {
  const IoUpdateHttpClient();

  @override
  Future<String> getText(Uri url, {String userAgent = updateUserAgent}) async {
    final bytes = await _get(url, userAgent);
    return utf8.decode(bytes);
  }

  @override
  Future<List<int>> getBytes(Uri url, {String userAgent = updateUserAgent}) =>
      _get(url, userAgent);

  Future<List<int>> _get(Uri url, String userAgent) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.headers.set(HttpHeaders.userAgentHeader, userAgent);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<List<int>>();
        throw StateError(
          'Update request returned status ${response.statusCode}',
        );
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }
}

/// The outcome of an update check.
enum UpdateStatus { skipped, upToDate, available, error }

class UpdateResult {
  const UpdateResult._({
    required this.status,
    this.release,
    this.message,
  });

  factory UpdateResult.skipped() => const UpdateResult._(
        status: UpdateStatus.skipped,
      );

  factory UpdateResult.upToDate(String version) => UpdateResult._(
        status: UpdateStatus.upToDate,
        message: 'Up to date · $version',
      );

  factory UpdateResult.available(UpdateRelease release) => UpdateResult._(
        status: UpdateStatus.available,
        release: release,
      );

  factory UpdateResult.error(String message) => UpdateResult._(
        status: UpdateStatus.error,
        message: message,
      );

  final UpdateStatus status;
  final UpdateRelease? release;
  final String? message;

  bool get isUpdate => status == UpdateStatus.available;
  bool get isError => status == UpdateStatus.error;
  bool get wasAttempted => status != UpdateStatus.skipped;
}

/// Checks for newer download builds.
///
/// There is no network access in the constructor. [check] is the only path
/// that makes a request, and it stops before doing so for store builds and
/// when automatic checks are switched off.
class UpdateChecker {
  UpdateChecker({
    required this.client,
    required this.platform,
    this.currentVersion = appVersion,
    this.storeBuild = isStoreBuild,
    this.autoCheckEnabled = true,
    Uri? endpoint,
  }) : endpoint = endpoint ?? updateEndpoint;

  final UpdateHttpClient client;
  final DownloadPlatform platform;
  final String currentVersion;
  final bool storeBuild;
  final Uri endpoint;

  /// Whether automatic checks are on. "Check now" can bypass this.
  bool autoCheckEnabled;

  /// Automatic checks run at most once in any twenty-four hour window.
  static const Duration checkInterval = Duration(hours: 24);

  bool isDue(String? lastCheckIso, DateTime now) {
    if (lastCheckIso == null) return true;
    final last = DateTime.tryParse(lastCheckIso);
    if (last == null) return true;
    return now.difference(last) >= checkInterval || last.isAfter(now);
  }

  /// Checks the release feed.
  ///
  /// Store builds and a switched-off automatic check return
  /// [UpdateStatus.skipped] without touching the client. [manual] bypasses the
  /// switch for the person's own "Check now" action, but never bypasses the
  /// store-build rule.
  Future<UpdateResult> check({bool manual = false}) async {
    if (storeBuild) return UpdateResult.skipped();
    if (!manual && !autoCheckEnabled) return UpdateResult.skipped();
    try {
      final text = await client.getText(endpoint);
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        return UpdateResult.error('The update response could not be read.');
      }
      final release = UpdateRelease.fromJson(decoded);
      if (release.tag.isEmpty || release.draft || release.prerelease) {
        return UpdateResult.upToDate(currentVersion);
      }
      if (compareVersions(release.tag, currentVersion) <= 0) {
        return UpdateResult.upToDate(currentVersion);
      }
      return UpdateResult.available(release);
    } catch (_) {
      return UpdateResult.error('The update check could not be completed.');
    }
  }
}

/// A verified file, ready to be written and opened.
class DownloadedUpdate {
  const DownloadedUpdate({required this.asset, required this.bytes});

  final UpdateAsset asset;
  final List<int> bytes;
}

/// Downloads this platform's file and refuses it unless its checksum matches
/// the one published in the same release.
class UpdateDownloader {
  const UpdateDownloader({
    required this.client,
    required this.platform,
    this.sumsAssetName = 'SHA256SUMS.txt',
  });

  final UpdateHttpClient client;
  final DownloadPlatform platform;
  final String sumsAssetName;

  Future<DownloadedUpdate> download(UpdateRelease release) async {
    final asset = pickAsset(release.assets, platform);
    if (asset == null || asset.url.isEmpty) {
      throw StateError('There is no download for this platform.');
    }
    final sums = release.assets
        .where((item) => item.name == sumsAssetName)
        .firstOrNull;
    if (sums == null || sums.url.isEmpty) {
      throw StateError('This release has no published checksums.');
    }
    final bytes = await client.getBytes(Uri.parse(asset.url));
    final sumsText = await client.getText(Uri.parse(sums.url));
    if (!verifyChecksum(bytes, sumsText, asset.name)) {
      throw StateError('The download did not match its published checksum.');
    }
    return DownloadedUpdate(asset: asset, bytes: bytes);
  }
}
