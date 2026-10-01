> **2026-10-01 — slice 1 landed (branch `feat/p6-core-host`).** A real
> transport now exists: `runtime/host/ezcore_core_host.c` (protocol in
> `ezcore_core_host_protocol.h`) and `lib/emu/process_session_backend.dart`,
> selected by the off-by-default `crashContainment` setting. Proven by the
> `core_host_contains_crash` ctest and `test/player_crash_containment_test.dart`.
> The "NOT implemented" list below is the spike's record and is now partly
> superseded: the transport, watchdog and setting exist; shared-memory frames,
> macOS/Android wiring and Windows verification do not.

# P6 Spike Notes — crash containment (ADR-015)

> Record of a **spike**, not a feature. One question: if a native core
> segfaults, does the host survive? Answer today: **no** — cores are dlopen'd
> into the app process (`runtime/src/dynload_posix.c:7`) and the worker
> isolate is explicitly not process isolation
> (`lib/emu/emulation_worker.dart:9-12`). This spike built the seam that a
> fix would plug into; it did not fix it.

## Design chosen

A **seam, not a transport**. `lib/emu/supervisor_session.dart` adds
`SupervisorSession`, which mirrors the `EmulationWorker` command surface
(`open`/`frame`/`pause`/`button`/`save`/`restore`/`cheats`/`reset`/`options`/
`setOption`/`close`, per `emulation_worker.dart:160-237`) so callers do not
change when the default flips.

- `ContainmentMode.inProcess` — today's path, **the default**, per ADR-015's
  requirement that containment ship behind a setting defaulting to current
  behaviour. Fully wired to `EmulationWorker`.
- `ContainmentMode.supervisedProcess` — the future path. Declared, and
  **throws `UnsupportedContainmentError`** rather than silently falling back.
  A loud failure is the honest state: nobody should believe containment is on
  when it is not.
- `isCrashContained` returns `false` for `inProcess`. The seam does not
  overclaim.
- A 30s watchdog wraps every command, matching today's `_request` timeout
  (`lib/emu/emulation_worker.dart:95`), and converts a `TimeoutException` into a
  `HungSessionException` after closing the session.

## Exit-code contract

Pure function `classifyExit({int? exitCode, Duration? watchdogAfter})`,
unit-tested with no FFI and no processes.

| Input | Outcome | Reasoning |
| --- | --- | --- |
| `exitCode == 0` | `clean` | ended without a signal |
| `exitCode == 9` | `crashed` | `kCrashExitCode` |
| `exitCode == null` | `crashed` | no evidence of a clean exit; fail-safe |
| other non-zero (e.g. `1`) | `clean` | a core calling `exit(1)` has not faulted |
| `watchdogAfter != null` | `hung` | checked **first** |

`kCrashExitCode = 9` is not invented: `runtime/test/test_core_boot.c:208-212`
already returns 9 for `WIFSIGNALED(status)`. Reusing it means the C harness and
the Dart classifier agree on one number.

**This contract now has automated coverage.** CTest test
`crash_signal_exit_code` (`runtime/test/test_crash_signal.c`, added to
`runtime/CMakeLists.txt`) drives the real fixture end to end: with
`EZCORE_CRASH_AFTER` unset the core must load and run 30 frames to a clean
exit 0, and with `EZCORE_CRASH_AFTER=3` set **in the forked child only** the
child must die on a real SIGSEGV that the same `WIFEXITED`/`WIFSIGNALED`
mapping classifies as 9. The clean case is the control: it is what makes the
crash case mean something, since a fixture that faulted unconditionally would
otherwise also "pass" the crash assertion. The test is POSIX-only
(`if(NOT WIN32)`) because it needs `fork()` to keep the faulting grandchild
from killing the runner; on Windows the fixture is still built but neither
half is asserted.

**What that coverage does NOT claim.** It is a fixture-level test. It proves
the crash fixture faults on demand and that the fork harness reports a signal
death as 9. It proves nothing about the app surviving a crash: no core is
isolated from a faulting one at app level, because
`ContainmentMode.supervisedProcess` still throws
`UnsupportedContainmentError` and no child process is ever spawned. A
maintainer seeing `crash_signal_exit_code` pass should conclude "the seam's
contract and its fixture are intact", not "the app is crash-safe".

**Watchdog outranks the exit code.** Killing a wedged child makes it die on
SIGKILL, which the supervisor would also report as a signal-derived 9. Without
the ordering rule a hang would file itself as a segfault bug report. A hang
produced no exit code of its own, so it is classified `hung`.

## Files

- `lib/emu/supervisor_session.dart` — the transport-agnostic seam.
- `runtime/test/crash_core.c` + `crash_libretro` CMake target — one binary,
  faults on the Nth `retro_run` when `EZCORE_CRASH_AFTER=N` is set, runs clean
  otherwise.
- `runtime/test/test_crash_signal.c` + CTest test
  `crash_signal_exit_code` — the automated proof that the fixture above still
  faults and that a signal death is classified as 9.
- `test/supervisor_session_test.dart` — classifier contract only.

## NOT implemented

- **No IPC transport.** No socket, pipe, or shared-memory protocol; no child
  process is ever spawned. `supervisedProcess` throws.
- **No frame/audio/save-state streaming** across a process boundary. Frames
  and PCM are copied by value today; a child would need a shared-memory path
  that does not exist yet.
- **No Windows support.** `dynload_win32.c` and no `CreateProcess` supervisor.
- **No cross-platform verification.** POSIX signals assumed throughout.
- **No supervisor, no watchdog process, no restart-on-crash, no crash
  reporting/telemetry.**
- **No setting wired to the UI.** `containment` is a constructor parameter
  only — no preferences key, no toggle.
- **No change to existing behaviour.** Nothing in `lib/emu/` or the player
  path was refactored to use `SupervisorSession`; it is additive and
  currently unreferenced by production code.

## Why the Dart test does not launch the crashing core

`crash_core.c` faults inside `retro_run`, which runs in *this* process once the
core is dlopen'd. Loading it from a Dart test would kill the whole `flutter
test` runner with SIGSEGV — not a clean failure, a truncated log and a dead
suite. Real-signal coverage must live where a process boundary already exists,
and that is what `runtime/test/test_crash_signal.c` does via
`test_core_boot.c`'s fork/waitpid pattern. The Dart test deliberately covers
the classifier alone; a future in-process containment change must add a forked
child-process test on the Dart side too, not extend the existing one.

## Unverified

Nothing was compiled or executed. See the delivery report; `libretro.h` is not
vendored in this worktree and Dart deps were never fetched, so both toolchains
had no way to check these files.

That still applies to the later addition of `test_crash_signal.c` and its
CTest registration: the test was written by reading `crash_core.c`,
`test_core_boot.c` and `test_input_reset.c`, but has never been built or run.
Its assertions are therefore an argument from the code, not an observed pass.
The first `ctest` run on a machine with vendored `libretro.h` is what will
actually confirm it.
