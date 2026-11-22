// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';

import 'package:ezcore/services/sha256.dart';
import 'package:ezcore/update/update_checker.dart';
import 'package:flutter_test/flutter_test.dart';

/// A client that records every request so tests can prove that no request is
/// made when one should not be.
class FakeHttpClient implements UpdateHttpClient {
  FakeHttpClient({
    this.text,
    this.bytes,
    this.textFor,
    this.bytesFor,
    this.fail = false,
  });

  String? text;
  List<int>? bytes;
  String Function(Uri url)? textFor;
  List<int> Function(Uri url)? bytesFor;
  bool fail;
  final List<Uri> calls = <Uri>[];

  @override
  Future<String> getText(Uri url, {String userAgent = updateUserAgent}) async {
    calls.add(url);
    if (fail) throw StateError('offline');
    final value = textFor?.call(url) ?? text;
    if (value == null) throw StateError('no response');
    return value;
  }

  @override
  Future<List<int>> getBytes(Uri url, {String userAgent = updateUserAgent}) async {
    calls.add(url);
    if (fail) throw StateError('offline');
    final value = bytesFor?.call(url) ?? bytes;
    if (value == null) throw StateError('no response');
    return value;
  }
}

Map<String, dynamic> releaseJson({
  String tag = 'v0.3.0',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, String>>? assets,
}) =>
    {
      'tag_name': tag,
      'body': 'First line of the notes.\nSecond line.',
      'draft': draft,
      'prerelease': prerelease,
      'html_url': 'https://github.com/0xJ1nn/ezcore/releases/tag/$tag',
      'assets': assets ?? const <Map<String, String>>[],
    };

Map<String, String> asset(String name) => {
      'name': name,
      'browser_download_url': 'https://downloads.example/$name',
      'size': '1234',
    };

void main() {
  group('version compare', () {
    test('orders versions numerically and ignores prefixes and suffixes', () {
      expect(compareVersions('v1.2.0', '1.2.0'), 0);
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('v1.2.0-beta.1', '1.2.0'), 0);
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('0.2.0', '0.3.0'), lessThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });
  });

  group('asset pick', () {
    final assets = <UpdateAsset>[
      UpdateAsset(name: 'ezcore-1.0-windows-x64.zip', url: 'https://x/a'),
      UpdateAsset(
        name: 'ezcore-1.0-windows-x64-installer.exe',
        url: 'https://x/b',
      ),
      UpdateAsset(name: 'ezcore-1.0-macos-arm64.dmg', url: 'https://x/c'),
      UpdateAsset(name: 'ezcore-1.0-x86_64.AppImage', url: 'https://x/d'),
      UpdateAsset(name: 'ezcore-1.0-linux-x64.tar.gz', url: 'https://x/e'),
      UpdateAsset(name: 'SHA256SUMS.txt', url: 'https://x/sums'),
    ];

    test('prefers the installer or disk image, then the archive', () {
      expect(
        pickAsset(assets, DownloadPlatform.windows)!.name,
        endsWith('.exe'),
      );
      expect(pickAsset(assets, DownloadPlatform.macos)!.name, endsWith('.dmg'));
      expect(
        pickAsset(assets, DownloadPlatform.linux)!.name,
        endsWith('.AppImage'),
      );
      expect(assets.firstWhere((a) => a.name.endsWith('.zip')).name,
          endsWith('.zip'));
      expect(assets.lastWhere((a) => a.name.endsWith('.tar.gz')).name,
          endsWith('.tar.gz'));
    });

    test('returns null when the platform has no file', () {
      expect(
        pickAsset([
          const UpdateAsset(name: 'notes.md', url: 'https://x/notes'),
        ], DownloadPlatform.linux),
        isNull,
      );
    });
  });

  group('checksum', () {
    final payload = utf8.encode('a release payload');
    final digest = sha256Hex(payload);
    final sums = '$digest  ezcore-1.0-windows-x64-installer.exe\n';

    test('accepts a matching digest and refuses anything else', () {
      expect(
        verifyChecksum(payload, sums, 'ezcore-1.0-windows-x64-installer.exe'),
        isTrue,
      );
      expect(verifyChecksum(payload, sums, 'another-file.exe'), isFalse);
      expect(
        verifyChecksum(utf8.encode('tampered'), sums,
            'ezcore-1.0-windows-x64-installer.exe'),
        isFalse,
      );
    });
  });

  group('check gating', () {
    test('a store build never makes a request', () async {
      final fake = FakeHttpClient(
        text: jsonEncode(releaseJson()),
      );
      final checker = UpdateChecker(
        client: fake,
        platform: DownloadPlatform.linux,
        storeBuild: true,
      );
      final result = await checker.check(manual: true);
      expect(result.status, UpdateStatus.skipped);
      expect(fake.calls, isEmpty);
    });

    test('switching automatic checks off makes no request', () async {
      final fake = FakeHttpClient(text: jsonEncode(releaseJson()));
      final checker = UpdateChecker(
        client: fake,
        platform: DownloadPlatform.linux,
        autoCheckEnabled: false,
      );
      final skipped = await checker.check();
      expect(skipped.status, UpdateStatus.skipped);
      expect(fake.calls, isEmpty);

      final manual = await checker.check(manual: true);
      expect(manual.status, UpdateStatus.available);
      expect(fake.calls, hasLength(1));
    });

    test('drafts, pre-releases and older tags are not updates', () async {
      for (final release in [
        releaseJson(draft: true),
        releaseJson(prerelease: true),
        releaseJson(tag: 'v0.1.0'),
        releaseJson(tag: 'v0.2.0'),
      ]) {
        final checker = UpdateChecker(
          client: FakeHttpClient(text: jsonEncode(release)),
          platform: DownloadPlatform.linux,
          currentVersion: '0.2.0',
        );
        final result = await checker.check(manual: true);
        expect(result.status, UpdateStatus.upToDate, reason: release.toString());
      }
    });

    test('a newer tag reports the release', () async {
      final checker = UpdateChecker(
        client: FakeHttpClient(text: jsonEncode(releaseJson())),
        platform: DownloadPlatform.linux,
        currentVersion: '0.2.0',
      );
      final result = await checker.check(manual: true);
      expect(result.status, UpdateStatus.available);
      expect(result.release!.tag, 'v0.3.0');
    });

    test('automatic checks are due at most once a day', () {
      final checker = UpdateChecker(
        client: FakeHttpClient(),
        platform: DownloadPlatform.macos,
      );
      final now = DateTime.utc(2026, 11, 19, 12);
      expect(checker.isDue(null, now), isTrue);
      expect(checker.isDue(now.toIso8601String(), now), isFalse);
      expect(
        checker.isDue(now.subtract(const Duration(hours: 23)).toIso8601String(),
            now),
        isFalse,
      );
      expect(
        checker.isDue(now.subtract(const Duration(hours: 25)).toIso8601String(),
            now),
        isTrue,
      );
    });
  });

  group('download', () {
    final payload = utf8.encode('verified payload');
    final digest = sha256Hex(payload);
    final release = UpdateRelease(
      tag: 'v0.3.0',
      body: '',
      assets: [
        UpdateAsset(name: 'app.exe', url: 'https://downloads.example/app.exe'),
        UpdateAsset(
          name: 'SHA256SUMS.txt',
          url: 'https://downloads.example/SHA256SUMS.txt',
        ),
      ],
    );

    test('returns the file only when its checksum matches', () async {
      final fake = FakeHttpClient(
        bytesFor: (_) => payload,
        textFor: (_) => '$digest  app.exe\n',
      );
      final downloader = UpdateDownloader(
        client: fake,
        platform: DownloadPlatform.windows,
      );
      final downloaded = await downloader.download(release);
      expect(downloaded.asset.name, 'app.exe');
      expect(downloaded.bytes, payload);
    });

    test('refuses a mismatched file', () async {
      final fake = FakeHttpClient(
        bytesFor: (_) => utf8.encode('not the published bytes'),
        textFor: (_) => '$digest  app.exe\n',
      );
      final downloader = UpdateDownloader(
        client: fake,
        platform: DownloadPlatform.windows,
      );
      await expectLater(
        downloader.download(release),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'message',
            contains('checksum'),
          ),
        ),
      );
    });
  });
}
