import 'package:ezcore/emu/supervisor_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// P6 spike: proves the exit-code contract that crash containment will be
/// judged by, WITHOUT crashing the test runner.
///
/// WHY THIS TEST NEVER LAUNCHES A CRASHING CORE
/// --------------------------------------------
/// `runtime/test/crash_core.c` faults inside `retro_run`, and cores are
/// dlopen'd into THIS process (runtime/src/dynload_posix.c:7). Loading it
/// in-process, even from a Dart isolate, would take down the entire `flutter
/// test` runner with SIGSEGV — the test would not fail, the suite would
/// simply vanish mid-run with a truncated log. A worker isolate is not a
/// process, so it cannot contain a native fault either
/// (lib/emu/emulation_worker.dart:9-12).
///
/// Real-signal coverage therefore lives where a process boundary already
/// exists: `runtime/test/test_core_boot.c` forks a child and maps
/// WIFSIGNALED -> exit code 9 (lines 184-212). This file deliberately tests
/// the CLASSIFIER ALONE as a pure function, with no FFI, no plugin, no
/// isolate, and no process. If a future change makes containment load a core
/// in-process, it must add a forked child-process test instead — not this one.
void main() {
  group('exit-code contract', () {
    test('exit code 0 is clean', () {
      final result = classifyExit(exitCode: 0);
      expect(result.outcome, SessionOutcome.clean);
      expect(result.exitCode, 0);
      expect(result.watchdogAfter, isNull);
    });

    test('the signal-derived crash code is crashed, not clean', () {
      // 9 is the sentinel test_core_boot.c returns for WIFSIGNALED.
      final result = classifyExit(exitCode: kCrashExitCode);
      expect(result.outcome, SessionOutcome.crashed);
      expect(result.exitCode, kCrashExitCode);
    });

    test('a non-sentinel non-zero exit is clean, not crashed', () {
      // A core that calls exit(1) has not faulted. Attributing that to a
      // memory-safety bug would poison crash telemetry.
      final result = classifyExit(exitCode: 1);
      expect(result.outcome, SessionOutcome.clean);
    });

    test('a missing exit code is failed-safe to crashed, never clean', () {
      final result = classifyExit();
      expect(result.outcome, SessionOutcome.crashed);
      expect(result.exitCode, isNull);
    });
  });

  group('hang is not a crash', () {
    test('a watchdog trip alone is hung', () {
      final result = classifyExit(watchdogAfter: const Duration(seconds: 30));
      expect(result.outcome, SessionOutcome.hung);
      expect(result.exitCode, isNull);
      expect(result.watchdogAfter, const Duration(seconds: 30));
    });

    test('a watchdog trip outranks a crash exit code', () {
      // Killing a wedged child makes it die on SIGKILL, which the supervisor
      // also reports as a signal. That must stay 'hung': a hang produced no
      // exit code of its own and conflating the two would let a wedged core
      // file itself as a segfault bug report.
      final result = classifyExit(
        exitCode: kCrashExitCode,
        watchdogAfter: const Duration(seconds: 5),
      );
      expect(result.outcome, SessionOutcome.hung);
      expect(result.exitCode, kCrashExitCode);
    });

    test('hung and crashed are genuinely distinct outcomes', () {
      expect(
        classifyExit(watchdogAfter: const Duration(seconds: 1)).outcome,
        isNot(SessionOutcome.crashed),
      );
      expect(
        classifyExit(exitCode: kCrashExitCode).outcome,
        isNot(SessionOutcome.hung),
      );
    });
  });

  group('SupervisorSession', () {
    test('defaults to the in-process path, as ADR-015 requires', () {
      // The setting must default to today's behaviour, so shipping cannot
      // change where cores run without an explicit opt-in.
      final session = SupervisorSession();
      expect(session.containment, ContainmentMode.inProcess);
      expect(session.containment, isNot(ContainmentMode.supervisedProcess));
    });

    test('the crash sentinel is the code test_core_boot.c already returns', () {
      // 9 is the existing fork/WIFSIGNALED sentinel; the C harness and this
      // classifier must agree or every crash looks clean.
      expect(kCrashExitCode, 9);
    });

    test('in-process mode reports that crashes are NOT contained', () {
      // Honest by construction: cores are dlopen'd into the app process
      // today, so this must not claim containment it does not have.
      expect(SupervisorSession().isCrashContained, isFalse);
    });

    test('supervised mode reports containment but refuses to fake it', () {
      // No transport exists yet, so the honest answer is a loud error rather
      // than a silent fall-back to in-process that would hide the gap.
      // Note: these are async, so the error surfaces on the returned future
      // — a sync `expect(() => ..., throwsA(...))` would not catch it.
      final session = SupervisorSession(
        containment: ContainmentMode.supervisedProcess,
      );
      expect(session.isCrashContained, isTrue);
      return expectLater(
        session.open(
          runtimeRef: const {},
          corePath: 'unused',
          contentPath: 'unused',
          systemDir: 'unused',
          saveDir: 'unused',
        ),
        throwsA(isA<UnsupportedContainmentError>()),
      );
    });

    test('commands before open are refused, not forwarded', () {
      return expectLater(
        SupervisorSession().frame(),
        throwsA(isA<StateError>()),
      );
    });

    test('reap routes through the same classifier', () {
      expect(
        SupervisorSession().reap(exitCode: 0).outcome,
        SessionOutcome.clean,
      );
      expect(
        SupervisorSession().reap(exitCode: kCrashExitCode).outcome,
        SessionOutcome.crashed,
      );
    });

    test('close is idempotent and safe with no session', () {
      // No backend was ever constructed, so this must not touch the runtime.
      final session = SupervisorSession();
      expect(session.isOpen, isFalse);
      return session.close().then((_) => session.close());
    });
  });

  test('classification string names its evidence', () {
    final text = classifyExit(
      exitCode: kCrashExitCode,
      watchdogAfter: const Duration(seconds: 2),
    ).toString();
    expect(text, contains('hung'));
    expect(text, contains('exitCode'));
  });
}
