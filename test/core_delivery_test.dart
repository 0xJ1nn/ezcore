// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:ezcore/cores/core_registry.dart';
import 'package:ezcore/models/core_manifest.dart';
import 'package:ezcore/screens/core_manager_screen.dart';
import 'package:ezcore/services/core_downloader.dart';
import 'package:ezcore/services/hash_verifier.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/core_path_resolver.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// On-demand delivery across platforms: stale-manifest recovery, every
/// refusal mode, and the plain sentences the Core Manager shows.

class _Dirs implements LocalDataDirProvider {
  _Dirs(this.dir);
  final Directory dir;

  @override
  Future<Directory> localDataDir() async => dir;

  @override
  String localDataDirPath() => dir.path;
}

class _RoutingFetcher implements CoreAssetFetcher {
  _RoutingFetcher(this.respond);
  final Stream<List<int>> Function(Uri url) respond;
  final List<Uri> seen = [];

  @override
  Stream<List<int>> open(Uri url) {
    seen.add(url);
    return respond(url);
  }
}

CoreManifest _giant(
  String pin, {
  String platformKey = 'linux-x64',
  String os = 'linux',
}) => CoreManifest(
  id: 'giant',
  name: 'Giant Core',
  version: '1.2.3',
  license: 'GPL-3.0-or-later',
  systems: ['testsystem'],
  extensions: ['gt'],
  cheatFamilies: const [],
  cheatsSupported: false,
  delivery: {
    os: 'download',
    if (os != 'linux') 'linux': 'absent',
    'android': 'absent',
    'ios': 'absent',
  },
  artifacts: {platformKey: pin},
);

Map<String, dynamic> _release({
  String repo = '0xJ1nn/ezcore',
  String platformKey = 'linux-x64',
  String? asset = 'giant_libretro-linux-x64.so',
}) => <String, dynamic>{
  'repo': repo,
  'tag': 'v9.9.9',
  'assets': <String, dynamic>{
    if (asset != null)
      platformKey: <String, dynamic>{'giant': asset},
  },
  'unavailablePlatforms': <String, dynamic>{
    'windows-x64': <String, dynamic>{
      'reason': 'assetsNotPublished',
      'message': 'No on-demand core assets are published for Windows yet.',
    },
  },
};

void main() {
  late Directory tmpDir;
  late _Dirs dirs;

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('ezcore_delivery');
    dirs = _Dirs(tmpDir);
  });

  tearDown(() async {
    if (tmpDir.existsSync()) await tmpDir.delete(recursive: true);
  });

  Future<String> pinOf(List<int> bytes) async {
    final f = File('${tmpDir.path}/pin-source')..writeAsBytesSync(bytes);
    return const DartHashVerifier().sha256File(f.path);
  }

  CoreDownloader downloader(
    CoreAssetFetcher fetcher, {
    bool Function()? isCancelled,
    int maxBytes = CoreDownloader.maxAssetBytes,
  }) => CoreDownloader(
    dirs: dirs,
    fetcher: fetcher,
    hashes: const DartHashVerifier(),
    isIOS: () => false,
    isCancelled: isCancelled,
    maxBytes: maxBytes,
  );

  Future<void> run(CoreDownloader dl, CoreManifest m, CoreRelease r,
      {String platformKey = 'linux-x64', CoreRegistry? registry}) {
    return dl.download(
      manifest: m,
      release: r,
      platformKey: platformKey,
      registry: registry ?? CoreRegistry(),
    );
  }

  group('repository fallback', () {
    test('a legacy owner builds the current-repository fallback URL', () {
      final r = CoreRelease.fromJson(_release(repo: 'JinUltimate1995/ezcore'));
      expect(r.usesLegacyOwner, isTrue);
      expect(
        r.downloadUri('linux-x64', 'giant').toString(),
        'https://github.com/JinUltimate1995/ezcore/releases/download/'
        'v9.9.9/giant_libretro-linux-x64.so',
      );
      expect(
        r.fallbackUri('linux-x64', 'giant')?.toString(),
        'https://github.com/0xJ1nn/ezcore/releases/download/'
        'v9.9.9/giant_libretro-linux-x64.so',
      );
      // Owner handles are matched without regard to case.
      expect(
        CoreRelease.fromJson(
          _release(repo: 'jinultimate1995/ezcore'),
        ).usesLegacyOwner,
        isTrue,
      );
    });

    test('a current repository never falls back to another owner', () {
      final r = CoreRelease.fromJson(_release());
      expect(r.usesLegacyOwner, isFalse);
      expect(r.fallbackUri('linux-x64', 'giant'), isNull);
    });

    test('a stale 404 is retried once and the verified bytes install',
        () async {
      final bytes = utf8.encode('bytes from the current repository');
      final pin = await pinOf(bytes);
      final fetcher = _RoutingFetcher((url) {
        if (url.path.startsWith('/JinUltimate1995/')) {
          return Stream<List<int>>.error(
            CoreAssetHttpException(404, url),
          );
        }
        return Stream.fromIterable([bytes.sublist(0, 5), bytes.sublist(5)]);
      });
      final registry = CoreRegistry();

      await run(downloader(fetcher), _giant(pin),
          CoreRelease.fromJson(_release(repo: 'JinUltimate1995/ezcore')),
          registry: registry);

      expect(fetcher.seen, hasLength(2));
      expect(fetcher.seen.first.path, contains('/JinUltimate1995/ezcore/'));
      expect(fetcher.seen.last.path, contains('/0xJ1nn/ezcore/'));
      expect(registry.isInstalled('giant'), isTrue);
      expect(
        File('${tmpDir.path}/cores/giant/giant.so').readAsBytesSync(),
        bytes,
      );
    });

    test('a checksum mismatch still refuses bytes fetched from the fallback',
        () async {
      final pin = await pinOf(utf8.encode('expected bytes'));
      final evil = utf8.encode('unexpected bytes');
      final fetcher = _RoutingFetcher((url) {
        if (url.path.startsWith('/JinUltimate1995/')) {
          return Stream<List<int>>.error(
            CoreAssetHttpException(404, url),
          );
        }
        return Stream.fromIterable([evil]);
      });
      final registry = CoreRegistry();

      await expectLater(
        run(
          downloader(fetcher),
          _giant(pin),
          CoreRelease.fromJson(_release(repo: 'JinUltimate1995/ezcore')),
          registry: registry,
        ),
        throwsA(isA<CoreDownloadException>().having(
          (e) => e.failure,
          'failure',
          CoreDownloadFailure.checksumMismatch,
        )),
      );
      expect(fetcher.seen, hasLength(2), reason: 'fallback was still attempted');
      expect(registry.isInstalled('giant'), isFalse);
      expect(File('${tmpDir.path}/cores/giant/giant.so').existsSync(), isFalse);
      expect(File('${tmpDir.path}/cores/giant/giant.so.part').existsSync(),
          isFalse);
    });

    test('a current-repository 404 reports the URL without retrying', () async {
      final pin = await pinOf(utf8.encode('x'));
      final fetcher = _RoutingFetcher(
        (url) => Stream<List<int>>.error(CoreAssetHttpException(404, url)),
      );

      await expectLater(
        run(downloader(fetcher), _giant(pin), CoreRelease.fromJson(_release())),
        throwsA(isA<CoreDownloadException>()
            .having((e) => e.failure, 'failure', CoreDownloadFailure.unreachable)
            .having((e) => e.message, 'message',
                allOf(contains('Tried https://github.com/0xJ1nn/ezcore/'),
                    contains('404')))),
      );
      expect(fetcher.seen, hasLength(1));
    });
  });

  group('failure modes', () {
    test('no asset for this platform', () async {
      final pin = await pinOf(utf8.encode('x'));
      final release = CoreRelease.fromJson(_release(asset: null));
      final fetcher = _RoutingFetcher((_) => Stream.fromIterable([utf8.encode('x')]));

      await expectLater(
        run(downloader(fetcher), _giant(pin, platformKey: 'windows-x64', os: 'windows'),
            release, platformKey: 'windows-x64'),
        throwsA(isA<CoreDownloadException>()
            .having((e) => e.failure, 'failure',
                CoreDownloadFailure.noAssetForPlatform)
            .having((e) => e.message, 'message', contains('not published'))),
      );
      expect(fetcher.seen, isEmpty);
    });

    test('unreachable transport reports the URL it tried', () async {
      final pin = await pinOf(utf8.encode('x'));
      final fetcher = _RoutingFetcher(
        (url) => Stream<List<int>>.error(
          const SocketException('offline'),
        ),
      );

      await expectLater(
        run(downloader(fetcher), _giant(pin), CoreRelease.fromJson(_release())),
        throwsA(isA<CoreDownloadException>()
            .having((e) => e.failure, 'failure', CoreDownloadFailure.unreachable)
            .having((e) => e.message, 'message',
                contains('Tried https://github.com/0xJ1nn/ezcore/'))),
      );
      expect(fetcher.seen, hasLength(1));
      expect(File('${tmpDir.path}/cores/giant/giant.so.part').existsSync(),
          isFalse);
    });

    test('an oversized payload is refused before hashing', () async {
      final pin = await pinOf(utf8.encode('x'));
      final fetcher = _RoutingFetcher(
        (_) => Stream.fromIterable([
          utf8.encode('123'),
          utf8.encode('456'),
        ]),
      );

      await expectLater(
        run(downloader(fetcher, maxBytes: 4), _giant(pin),
            CoreRelease.fromJson(_release())),
        throwsA(isA<CoreDownloadException>().having(
          (e) => e.failure,
          'failure',
          CoreDownloadFailure.tooLarge,
        )),
      );
      expect(File('${tmpDir.path}/cores/giant/giant.so.part').existsSync(),
          isFalse);
    });

    test('cancellation stops the stream and leaves no partial file', () async {
      final pin = await pinOf(utf8.encode('expected'));
      late final CoreDownloader dl;
      dl = downloader(
        _RoutingFetcher((_) async* {
          yield utf8.encode('first');
          dl.cancelDownload();
          yield utf8.encode('second');
        }),
      );

      await expectLater(
        run(dl, _giant(pin), CoreRelease.fromJson(_release())),
        throwsA(isA<CoreDownloadException>().having(
          (e) => e.failure,
          'failure',
          CoreDownloadFailure.cancelled,
        )),
      );
      expect(File('${tmpDir.path}/cores/giant/giant.so.part').existsSync(),
          isFalse);
    });

    test('a cancelled token is reset for the next attempt', () async {
      final bytes = utf8.encode('next attempt');
      final pin = await pinOf(bytes);
      final dl = downloader(_RoutingFetcher((_) => Stream.fromIterable([bytes])));
      dl.cancelDownload();
      dl.resetCancellation();

      await run(dl, _giant(pin), CoreRelease.fromJson(_release()));
      expect(File('${tmpDir.path}/cores/giant/giant.so').existsSync(), isTrue);
    });

    test('each failure has exactly one plain sentence for the UI', () {
      expect(CoreDownloadFailure.values, hasLength(5));
      for (final failure in CoreDownloadFailure.values) {
        expect(failure.sentence, endsWith('.'), reason: failure.name);
        expect(failure.sentence, isNot(contains('\n')), reason: failure.name);
        expect(failure.sentence, isNot(contains('Exception')),
            reason: failure.name);
      }
    });
  });

  group('explicit platform availability in the generated release map', () {
    test('every buildable platform is published or named as absent', () {
      final raw = File('cores/release.json').readAsStringSync();
      final jsonMap = json.decode(raw) as Map<String, dynamic>;
      final release = CoreRelease.fromJson(jsonMap);
      final assets = jsonMap['assets'] as Map<String, dynamic>;
      final absent = jsonMap['unavailablePlatforms'] as Map<String, dynamic>;

      expect(assets.keys.toSet(), {'linux-x64'});
      expect(absent.keys.toSet(), {
        'macos-arm64',
        'windows-x64',
        'android-arm64',
        'ios-arm64',
      });
      expect(
        {...assets.keys, ...absent.keys},
        {
          'macos-arm64',
          'windows-x64',
          'android-arm64',
          'ios-arm64',
          'linux-x64',
        },
      );
      expect(release.hasAssetsFor('linux-x64'), isTrue);
      expect(release.hasAssetsFor('windows-x64'), isFalse);
      expect(
        release.unavailableMessage('windows-x64'),
        contains('Install a core from a file instead'),
      );
      expect(release.unavailableMessage('ios-arm64'),
          'On-demand core downloads are not offered on iOS.');
    });

    test('every offered core is pinned to the bytes the release serves', () {
      // The app verifies a download against the catalog pin. A pin that
      // disagrees with the asset on the tag makes the download succeed and
      // then be discarded on every attempt, with no way for the person to
      // tell it apart from a corrupt transfer.
      final published = <String, String>{};
      for (final line in File('cores/published-sha256.txt')
          .readAsLinesSync()) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length == 2 && !line.trimLeft().startsWith('#')) {
          published[parts[1]] = parts[0].toLowerCase();
        }
      }
      final release =
          json.decode(File('cores/release.json').readAsStringSync())
              as Map<String, dynamic>;
      final assets = release['assets'] as Map<String, dynamic>;
      final catalog =
          json.decode(File('cores/catalog.json').readAsStringSync())
              as Map<String, dynamic>;

      expect(assets, isNotEmpty, reason: 'the release map publishes something');
      for (final platform in assets.keys) {
        final offered = assets[platform] as Map<String, dynamic>;
        for (final entry in offered.entries) {
          final pin = ((catalog[entry.key]['artifacts'] ??
                  <String, dynamic>{})[platform] as String?)
              ?.toLowerCase();
          final digest = published[entry.value];
          expect(digest, isNotNull,
              reason: '${entry.value} is not in the published checksum file');
          expect(pin, digest,
              reason: '${entry.key} on $platform: catalog pin must be the '
                  'bytes the release serves');
        }
      }
    });
  });

  group('Core Manager wording', () {
    testWidgets('an absent download platform says so instead of offering install',
        (tester) async {
      final state = AppState.ephemeral();
      final key = CorePathResolver.currentPlatformKey();
      final os = key.split('-').first;
      final m = _giant('pin', platformKey: key, os: os);
      state.registry.loadCatalog({m.id: json.encode(m.toJson())});
      // No assets at all for this host: release metadata says why.
      state.coreRelease = CoreRelease.fromJson(<String, dynamic>{
        'repo': '0xJ1nn/ezcore',
        'tag': 'v0.0.0',
        'assets': <String, dynamic>{},
        'unavailablePlatforms': <String, dynamic>{
          key: <String, dynamic>{
            'reason': 'assetsNotPublished',
            'message': 'No on-demand core assets are published here.',
          },
        },
      });

      await tester.pumpWidget(MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: CoreManagerScreen(state: state)),
      ));
      await tester.tap(find.text('Available'));
      await tester.pump();

      expect(find.text('No on-demand core assets are published here.'),
          findsWidgets);
      expect(find.text('Not installed · ready to install'), findsNothing);
    });

    testWidgets('a refused install shows the failure sentence in a dialog',
        (tester) async {
      final fetcher = _RoutingFetcher(
        (_) => Stream.fromIterable([utf8.encode('tampered')]),
      );
      final state = AppState.internal(
        persistence: null,
        saves: MemorySaveSyncProvider(),
        downloader: downloader(fetcher),
      );
      final key = CorePathResolver.currentPlatformKey();
      final os = key.split('-').first;
      // Real file I/O must run outside the widget test's fake-async zone.
      final pin = await tester.runAsync(() => pinOf(utf8.encode('expected')));
      if (pin == null) fail('could not compute the pin');
      final m = _giant(pin, platformKey: key, os: os);
      state.registry.loadCatalog({m.id: json.encode(m.toJson())});
      state.coreRelease = CoreRelease.fromJson(_release(platformKey: key));

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(body: CoreManagerScreen(state: state)),
      ));
      await tester.tap(find.text('Available'));
      await tester.pump();
      await tester.tap(find.text('Install'));
      // Alternate fake-async frames with real event-loop time: the
      // downloader suspends on both widget frames and disk I/O.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        if (find.byType(AlertDialog).evaluate().isNotEmpty) break;
      }
      expect(find.byType(AlertDialog), findsOneWidget);
      // Once in the card's status line, once in the dialog.
      expect(find.text(CoreDownloadFailure.checksumMismatch.sentence),
          findsNWidgets(2));
      // The status line carries the same sentence once the dialog closes.
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(CoreDownloadFailure.checksumMismatch.sentence),
          findsWidgets);
    }, timeout: const Timeout(Duration(seconds: 90)));
  });
}
