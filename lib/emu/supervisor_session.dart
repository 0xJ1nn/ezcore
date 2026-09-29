import 'dart:async';
import 'dart:typed_data';

import 'emulation_worker.dart';

/// Where a libretro core runs, from the host's point of view.
///
/// ADR-015 requires containment to ship behind a setting that defaults to
/// today's path, so [inProcess] is the first value and the default for every
/// field and constructor in this file.
enum ContainmentMode {
  /// Today's behaviour: the core is dlopen'd into this process and driven from
  /// a Dart isolate. Fast, no IPC, and a native crash still kills the app.
  inProcess,

  /// Planned behaviour (P6): the core is driven inside a supervised child
  /// process, so a segfault becomes a child exit code the host can observe.
  /// The seam exists in this spike; the transport does not — see
  /// .ezcore/P6_SPIKE_NOTES.md.
  supervisedProcess,
}

/// What the host can prove about a session that has ended.
enum SessionOutcome {
  /// The session process ended without a signal. Non-zero codes that are not
  /// the crash sentinel still land here: the core chose to `exit()`, which is
  /// not a fault we can attribute to a memory-safety bug.
  clean,

  /// The session died on a signal (SIGSEGV/SIGABRT/SIGBUS/…), or the host
  /// could not prove the session ended normally. Fail-safe default.
  crashed,

  /// The session stopped making progress and was reaped by the watchdog.
  /// Deliberately NOT [crashed]: a hang has produced no exit code, and
  /// conflating the two would let a wedged core masquerade as a bug report.
  hung,
}

/// Exit code the POSIX supervisor reports for a signal death.
///
/// 9 is not arbitrary — it is the sentinel `runtime/test/test_core_boot.c`
/// already returns when `WIFSIGNALED(status)` is true, so the C harness and
/// this Dart classifier agree on one number.
const int kCrashExitCode = 9;

/// Outcome of a session, with the raw evidence that produced it.
class ExitClassification {
  const ExitClassification(this.outcome, this.exitCode, {this.watchdogAfter});

  final SessionOutcome outcome;

  /// Raw child exit code, or null when no code was ever observed.
  final int? exitCode;

  /// How long the watchdog waited before declaring a hang, when it did.
  final Duration? watchdogAfter;

  @override
  String toString() =>
      'ExitClassification(${outcome.name}, exitCode: $exitCode'
      '${watchdogAfter == null ? '' : ', watchdog: ${watchdogAfter!.inMilliseconds}ms'})';
}

/// Pure classifier — no processes, no isolates, no plugins. Every rule lives
/// here so it can be unit-tested without crashing the test runner.
///
/// Order matters: the watchdog verdict is checked BEFORE the exit code,
/// because a reaped hang usually also carries a signal-derived code and must
/// not be reported as a crash.
ExitClassification classifyExit({
  int? exitCode,
  Duration? watchdogAfter,
}) {
  if (watchdogAfter != null) {
    return ExitClassification(
      SessionOutcome.hung,
      exitCode,
      watchdogAfter: watchdogAfter,
    );
  }
  if (exitCode == null) {
    // No code and no watchdog: the session vanished without evidence. We
    // cannot prove the host stayed healthy, so we do not call it clean.
    return ExitClassification(SessionOutcome.crashed, null);
  }
  if (exitCode == kCrashExitCode) {
    return ExitClassification(SessionOutcome.crashed, exitCode);
  }
  return ExitClassification(SessionOutcome.clean, exitCode);
}

/// Thrown when a session is reaped by the watchdog.
class HungSessionException implements Exception {
  HungSessionException(this.classification);

  final ExitClassification classification;

  @override
  String toString() => 'Session hung: $classification';
}

/// Thrown when a command is issued against a mode that has no transport yet.
class UnsupportedContainmentError extends UnsupportedError {
  UnsupportedContainmentError(ContainmentMode mode, String command)
    : super(
        'Command "$command" is not implemented for ContainmentMode.${mode.name}. '
        'This spike ships the seam only — no IPC transport exists yet. '
        'See .ezcore/P6_SPIKE_NOTES.md.',
      );
}

/// One emulation session addressed by containment mode instead of by
/// transport. The command surface mirrors [EmulationWorker] exactly, so
/// callers (player controller, save-state UI, options sheet) do not change
/// when the default flips to a child process.
///
/// SPIKE SCOPE: [ContainmentMode.inProcess] is fully wired to
/// [EmulationWorker]. [ContainmentMode.supervisedProcess] is a declared seam
/// that throws [UnsupportedContainmentError] — deliberately loud rather than
/// silently falling back, so nobody believes containment is on when it is not.
class SupervisorSession {
  /// The in-process worker this session delegates to. Ignored when
  /// [containment] is [ContainmentMode.supervisedProcess], which is still
  /// unsupported.
  final EmulationWorker? worker;

  SupervisorSession({
    this.containment = ContainmentMode.inProcess,
    this.watchdogTimeout = const Duration(seconds: 30),
    this.worker,
  });

  /// Defaults to today's path. Changing it is a user/ADR-015 decision.
  final ContainmentMode containment;

  /// How long a single command may take before the session is declared hung.
  final Duration watchdogTimeout;

  bool _open = false;
  bool _closed = false;

  EmulationWorker? _ownedWorker;
  EmulationWorker get _backend =>
      worker ?? (_ownedWorker ??= EmulationWorker());

  bool get isOpen => _open;

  /// True only when a crash in the core provably cannot take down the host.
  /// False today: cores are dlopen'd into the app process
  /// (runtime/src/dynload_posix.c:7) and the isolate is not process
  /// isolation (lib/emu/emulation_worker.dart:9-12).
  bool get isCrashContained => containment == ContainmentMode.supervisedProcess;

  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
  }) async {
    if (_open) throw StateError('Session already open');
    _check('open');
    final result = await _guard(
      () => _backend.open(
        runtimeRef: runtimeRef,
        corePath: corePath,
        contentPath: contentPath,
        systemDir: systemDir,
        saveDir: saveDir,
      ),
    );
    _open = true;
    return result;
  }

  /// One frame (1..8), or null when the core produced no frame (e.g. paused).
  Future<Map<String, dynamic>?> frame({int count = 1}) async {
    _requireOpen('frame');
    return _guard(() => _backend.frame(count: count));
  }

  Future<void> pause(bool value) async {
    _requireOpen('pause');
    await _guard(() => _backend.pause(value));
  }

  Future<void> button(int id, bool pressed) async {
    _requireOpen('button');
    await _guard(() => _backend.button(id, pressed));
  }

  Future<Uint8List> save() async {
    _requireOpen('save');
    return _guard(_backend.save);
  }

  Future<void> restore(Uint8List bytes) async {
    _requireOpen('restore');
    await _guard(() => _backend.restore(bytes));
  }

  /// Returns the indices the runtime could not dispatch to a core hook.
  Future<List<int>> applyCheats(List<List<Object>> cheats) async {
    _requireOpen('cheats');
    return _guard(() => _backend.applyCheats(cheats));
  }

  Future<void> reset() async {
    _requireOpen('reset');
    await _guard(_backend.reset);
  }

  Future<List<Map<String, String>>> coreOptions() async {
    _requireOpen('options');
    return _guard(_backend.coreOptions);
  }

  Future<bool> setCoreOption(String key, String value) async {
    _requireOpen('setOption');
    return _guard(() => _backend.setCoreOption(key, value));
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final wasOpen = _open;
    _open = false;
    if (wasOpen) await _backend.close();
  }

  /// Reaps an ended session and reports what the host can prove about it.
  ExitClassification reap({int? exitCode, Duration? watchdogAfter}) =>
      classifyExit(exitCode: exitCode, watchdogAfter: watchdogAfter);

  void _requireOpen(String command) {
    if (_open) return;
    _check(command);
    throw StateError('No open session for "$command"');
  }

  void _check(String command) {
    if (containment != ContainmentMode.inProcess) {
      throw UnsupportedContainmentError(containment, command);
    }
  }

  /// Applies the watchdog. A timeout is reported as [HungSessionException]
  /// and the session is closed so a wedged core cannot keep the host pinned.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(watchdogTimeout);
    } on TimeoutException {
      final classification = classifyExit(watchdogAfter: watchdogTimeout);
      await close();
      throw HungSessionException(classification);
    }
  }
}
