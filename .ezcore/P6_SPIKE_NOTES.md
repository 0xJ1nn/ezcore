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
  (`emulation_worker.dart:56-57`), and converts a `TimeoutException` into a
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

**Watchdog outranks the exit code.** Killing a wedged child makes it die on
SIGKILL, which the supervisor would also report as a signal-derived 9. Without
the ordering rule a hang would file itself as a segfault bug report. A hang
produced no exit code of its own, so it is classified `hung`.

## Files

- `lib/emu/supervisor_session.dart` — the transport-agnostic seam.
- `runtime/test/crash_core.c` + `crash_libretro` CMake target — one binary,
  faults on the Nth `retro_run` when `EZCORE_CRASH_AFTER=N` is set, runs clean
  otherwise.
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
suite. Real-signal coverage must live where a process boundary already exists:
`test_core_boot.c`'s fork/waitpid harness. The Dart test deliberately covers
the classifier alone; a future in-process containment change must add a forked
child-process test, not extend this one.

## Unverified

Nothing was compiled or executed. See the delivery report; `libretro.h` is not
vendored in this worktree and Dart deps were never fetched, so both toolchains
had no way to check these files.
