// P6 (ADR-015): a core session hosted in a separate process.
//
// These tests drive the real `ezcore_core_host` binary. The crash case is
// the point: the crashing core faults inside the HOST process, so this test
// runner must keep running and must learn what happened. (Loading the crash
// core in-process here would kill the runner — that is exactly the failure
// this backend exists to prevent.) Skips cleanly when the native pieces are
// not built.
import 'dart:io';
import 'dart:typed_data';

import 'package:ezcore/emu/process_session_backend.dart';
import 'package:ezcore/emu/supervisor_session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_paths.dart' as paths;

void main() {
  final dir = paths.runtimeBuildDir();
  String? art(String name) {
    if (dir == null) return null;
    final f = File('$dir/$name');
    return f.existsSync() ? f.absolute.path : null;
  }

  final host = art(
    Platform.isWindows ? 'ezcore_core_host.exe' : 'ezcore_core_host',
  );
  final synth = art('libsynth_libretro.${paths.hostLibExt}');
  final crash = art('libcrash_libretro.${paths.hostLibExt}');
  final built = host != null && synth != null && crash != null;
  final skip = built
      ? null
      : 'needs built ezcore_core_host + synth/crash cores';

  Future<Map<String, dynamic>> open(ProcessSessionBackend b, String core) =>
      b.open(
        runtimeRef: const {'kind': 'path', 'path': null},
        corePath: core,
        contentPath: '/dev/null',
        systemDir: Directory.systemTemp.path,
        saveDir: Directory.systemTemp.path,
      );

  test(
    'a well-behaved core works end to end through the host',
    skip: skip,
    () async {
      final b = ProcessSessionBackend(hostPath: host!);
      final info = await open(b, synth!);
      expect(info['width'], 256);
      expect(info['height'], 240);
      expect(info['fps'], 60.0);

      final packet = await b.frame();
      expect(packet, isNotNull);
      expect((packet!['rgba'] as Uint8List).length, 256 * 240 * 4);
      expect((packet['pcm'] as Uint8List).length, greaterThan(0));

      await b.button(0, true, port: 1);
      final state = await b.save();
      expect(state, isNotEmpty);
      await b.restore(state);
      expect(await b.coreOptions(), isA<List>());
      expect(await b.setCoreOption('no_such_option', 'x'), isFalse);
      expect(await b.applyCheats(const []), isEmpty);
      await b.reset();

      await b.pause(true);
      expect(
        await b.frame(),
        isNull,
        reason: 'a paused session returns no frame',
      );
      await b.pause(false);

      await b.close();
      expect(b.lastExit?.outcome, SessionOutcome.clean);
    },
  );

  test(
    'a crashing core ends the session, not this process',
    skip: skip,
    () async {
      final b = ProcessSessionBackend(
        hostPath: host!,
        environment: const {'EZCORE_CRASH_AFTER': '3'},
      );
      await open(b, crash!);
      expect(await b.frame(), isNotNull);
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

  test(
    'a host that stops answering is reaped as hung, not crashed',
    skip: Platform.isWindows ? 'uses /bin/sleep' : null,
    () async {
      final b = ProcessSessionBackend(
        hostPath: '/bin/sleep',
        arguments: const ['30'],
        watchdog: const Duration(milliseconds: 300),
        openWatchdog: const Duration(milliseconds: 300),
      );
      await expectLater(
        open(b, '/nonexistent'),
        throwsA(
          isA<CoreSessionEndedException>().having(
            (e) => e.classification.outcome,
            'outcome',
            SessionOutcome.hung,
          ),
        ),
      );
      expect(b.lastExit?.outcome, SessionOutcome.hung);
      await b.close();
    },
  );

  test(
    'an error answer is a normal failure; the session stays usable',
    skip: skip,
    () async {
      final b = ProcessSessionBackend(hostPath: host!);
      await expectLater(
        open(b, '/nonexistent/core.so'),
        throwsA(isA<StateError>()),
      );
      // The host is still alive and can open a real core afterwards.
      final info = await open(b, synth!);
      expect(info['width'], 256);
      await b.close();
    },
  );

  test('Dart reports a signal death as a negative exit code: crashed', () {
    expect(classifyExit(exitCode: -11).outcome, SessionOutcome.crashed);
    expect(classifyExit(exitCode: -6).outcome, SessionOutcome.crashed);
  });
}
