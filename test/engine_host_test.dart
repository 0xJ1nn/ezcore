// Tier-2 proof: a NON-libretro engine behind the SAME wire protocol, launched
// and driven by the existing ProcessSessionBackend. The engine is selected by
// data (--engine=synthetic); no protocol op, no Dart client code changes.
// Skips cleanly when the native host has not been built.
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/emu/process_session_backend.dart';
import 'package:ezcore/emu/supervisor_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_paths.dart' as paths;

int _hash(Uint8List bytes) {
  var h = 2166136261;
  for (final b in bytes) {
    h ^= b;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

void main() {
  final dir = paths.runtimeBuildDir();
  final hostPath = dir == null
      ? null
      : '$dir/${Platform.isWindows ? 'ezcore_core_host.exe' : 'ezcore_core_host'}';
  final host = (hostPath != null && File(hostPath).existsSync()) ? hostPath : null;
  final built = host != null;
  final skip = built ? null : 'needs built ezcore_core_host';

  ProcessSessionBackend backend({Map<String, String>? environment}) =>
      ProcessSessionBackend(
        hostPath: host!,
        arguments: const ['--engine=synthetic'],
        environment: environment,
      );

  Future<Map<String, dynamic>> open(ProcessSessionBackend b) => b.open(
    runtimeRef: const {'kind': 'path', 'path': null},
    corePath: 'synthetic://tier2-proof',
    contentPath: '/dev/null', // no ROM: the content id is data
    systemDir: Directory.systemTemp.path,
    saveDir: Directory.systemTemp.path,
  );

  test(
    'a non-libretro engine works end to end through ProcessSessionBackend',
    skip: skip,
    () async {
      final b = backend();
      final info = await open(b);
      expect(info['name'], 'Synthetic Tier-2 Engine');
      expect(info['width'], 256);
      expect(info['height'], 240);
      expect(info['fps'], 60.0);

      final first = await b.frame();
      expect(first, isNotNull);
      expect((first!['rgba'] as Uint8List).length, 256 * 240 * 4);
      expect((first['pcm'] as Uint8List).length, greaterThan(0));
      final hashA = _hash(first['rgba'] as Uint8List);

      await b.button(0, true);
      final pressed = await b.frame();
      expect(_hash(pressed!['rgba'] as Uint8List), isNot(hashA),
          reason: 'BUTTON reached the engine and changed its frame');

      await b.button(0, false);
      final released = await b.frame();
      expect(_hash(released!['rgba'] as Uint8List), hashA,
          reason: 'the pattern is deterministic for the same inputs');

      final state = await b.save();
      expect(state, isNotEmpty);
      await b.button(0, true);
      await b.restore(state);
      final restored = await b.frame();
      expect(_hash(restored!['rgba'] as Uint8List), hashA,
          reason: 'RESTORE rolled back the engine state');

      expect(await b.coreOptions(), isNotEmpty);
      expect(await b.setCoreOption('pattern', 'checker'), isTrue);
      await b.close();
      expect(b.lastExit?.outcome, SessionOutcome.clean);
    },
  );

  test(
    'an engine crash is reported as a crash; this process survives',
    skip: skip,
    () async {
      final b = backend(environment: const {'EZCORE_CRASH_AFTER': '2'});
      await open(b);
      expect(await b.frame(), isNotNull);
      await expectLater(
        b.frame(),
        throwsA(
          isA<CoreSessionEndedException>().having(
            (e) => e.classification.outcome,
            'outcome',
            SessionOutcome.crashed,
          ),
        ),
      );
      expect(b.lastExit?.outcome, SessionOutcome.crashed);
      // Every later command fails fast with the same verdict.
      await expectLater(b.frame(), throwsA(isA<CoreSessionEndedException>()));
      // And we are, demonstrably, still here.
      expect(1 + 1, 2);
      await b.close();
    },
  );
}
