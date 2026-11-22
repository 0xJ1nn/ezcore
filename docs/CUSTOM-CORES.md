# Writing your own ezCORE core

ezCORE runs libretro cores as replaceable modules. If you have a libretro core
that already builds, you can package it, install it from a folder, and share it
under your own name and licence. This guide describes the package the app
accepts, how to produce its library for each platform, and the limits the
project applies.

For the contributor workflow that adds a core to the repository and ships it in
official builds, see [CORE_AUTHORING.md](CORE_AUTHORING.md). The full package
contract is [PACKAGE_FORMAT.md](PACKAGE_FORMAT.md).

## What a core is here

A core is a native library that implements the libretro API v1: it exports the
`retro_*` entry points and reports `RETRO_API_VERSION == 1`. ezCORE does not add
a core SDK. A core does not implement or call the `ezcore_*` host API, and it
never depends on Flutter. Using the libretro contract is what makes the same
core usable by ezCORE and by other frontends.

The library is described by data. A package is a directory whose name is the
core's `id`:

```
<core-id>/
  manifest.json
  <core-id>_libretro.so|.dylib|.dll
  info/<core-id>.info        # optional libretro metadata
  layouts/                   # optional on-screen layouts (ezcore.controls/1)
  system/<name>/             # optional core-owned data, declared in system_data
```

Everything except the library is data: no scripts, no symlinks, no fetched
URLs. ZIP packages are not supported; the installer takes a folder.

## Manifest fields

`manifest.json` is a single JSON object. Only the fields below are accepted;
any other top-level key fails validation.

| Field | Type | Required by | Meaning |
|---|---|---|---|
| `id` | string | validator, catalog | Stable identifier; `[a-z0-9_]+`, equal to the package directory name |
| `name` | string | catalog | Display name |
| `version` | string | catalog | Upstream version, for example `"1.0.0"` |
| `license` | string | catalog | Licence expression for the core |
| `license_url` | string | optional | Link to the licence text |
| `homepage` | string | optional | Project homepage |
| `upstream` | string | optional | Upstream project path |
| `systems` | string[] | catalog | System short codes the core runs |
| `extensions` | string[] | optional | File extensions it opens |
| `cheats_supported` | bool | optional | Whether the core supports cheats |
| `cheat_families` | string[] | optional | Supported cheat family identifiers |
| `bios_required` | bool | optional | Whether firmware is needed; names only, never content |
| `bios_files` | string[] | optional | Exact expected firmware filenames |
| `bios_notes` | string | optional | Guidance about firmware the user supplies |
| `delivery` | object | catalog | Per-OS delivery strategy |
| `artifacts` | object | install | Per-platform SHA-256 pin of the library bytes |
| `execution` | object | optional | Per-OS strategy: `interpreter` or `dynarec` |
| `provenance` | object | optional | `built_from`, `upstream_license`, `relationship` |
| `blocked_reason` | string | hold cores | Why a core is under a legal or IP hold |
| `gated_reason` | string | gated cores | Why the project distributes only the recipe |
| `notes` | string | optional | Free-form operator notes |
| `default_options` | object | optional | Starting values for the core's own options |
| `system_data` | string[] | optional | Core-owned folders supplied under `system/` |

A complete example, using only accepted fields:

```json
{
  "id": "mycore",
  "name": "My Core",
  "version": "1.0.0",
  "license": "MIT",
  "license_url": "https://example.com/mycore/LICENSE",
  "homepage": "https://example.com/mycore",
  "upstream": "someone/mycore",
  "systems": ["gb", "gbc"],
  "extensions": ["gb", "gbc", "zip"],
  "cheats_supported": false,
  "cheat_families": [],
  "bios_required": false,
  "bios_files": [],
  "bios_notes": "No firmware required.",
  "delivery": {
    "macos": "absent",
    "windows": "absent",
    "linux": "absent",
    "android": "absent",
    "ios": "absent"
  },
  "artifacts": {
    "macos-arm64": "<sha256 of the macOS arm64 library>",
    "linux-x64": "<sha256 of the Linux x64 library>"
  },
  "execution": {
    "macos": "interpreter",
    "windows": "interpreter",
    "linux": "interpreter",
    "android": "interpreter",
    "ios": "interpreter"
  },
  "provenance": {
    "built_from": "https://example.com/mycore",
    "upstream_license": "MIT",
    "relationship": "independent build; not affiliated with the upstream project"
  }
}
```

### The delivery map

`delivery` maps an operating system (`macos`, `windows`, `linux`, `android`,
`ios`) to one of three values:

| Value | Meaning |
|---|---|
| `bundled` | Ships inside the app bundle or APK |
| `download` | Fetched on demand from a release asset and verified against the pin |
| `absent` | Not distributed by the project |

The value `on-demand` is not accepted. iOS is never `download`: cores are built
into the app and nothing is fetched at runtime. A core you build and install
yourself does not become distributed by the project; the project's own cores use
these values to describe what their releases ship.

### The execution map

`execution` maps an operating system to `interpreter` or `dynarec`. A dynamic
recompiler is faster but needs JIT, which the App Store does not allow, so iOS
must be `interpreter`. Missing entries mean the strategy is unknown.

### Pins and optional data

Each `artifacts` value is a SHA-256 digest: 64 lowercase hexadecimal characters
of the exact library bytes. The app compares it with the library before it
stages any code. `bios_required`, `bios_files` and `bios_notes` name firmware the
user supplies; the project never ships firmware. `default_options` and
`system_data` are data only: the first sets starting values for options the core
declares, the second names folders of the core's own data placed in the system
directory. Neither may contain code, BIOS, firmware or keys.

## Pinning artifacts with SHA-256

Build the library, then hash the exact bytes you will distribute. On macOS and
Linux:

```bash
shasum -a 256 <core-id>_libretro.dylib   # macOS
sha256sum <core-id>_libretro.so          # Linux
```

Put the resulting 64-character digest in `artifacts` under the matching
platform-architecture key. The repository's own cores are pinned by
`scripts/pin_artifacts.py`, which writes the digest into the manifest and
regenerates the catalog:

```bash
python3 scripts/pin_artifacts.py macos-arm64 --out native/cores
python3 scripts/pin_artifacts.py linux-x64
python3 scripts/pin_artifacts.py linux-x64 --check
```

On macOS the built library is ad-hoc signed during staging, so the pin describes
the signed bytes. Never re-sign a pinned library: signing changes the bytes and
the app will refuse them. A core with `blocked_reason` cannot be pinned.

## Building the library for each platform

The repository builds its bundled cores with `scripts/build_core.sh`, which
dispatches `<core-id>` to a `build_<core-id>()` recipe defined in that script.
That command cannot build a core of your own: an id without a recipe fails with
`build_<core-id>: command not found`. Compile your source directly instead,
keeping the `<core-id>_libretro.<ext>` name the app recognises.

Fetch the libretro header from a repository checkout, then compile from that
checkout root:

```bash
scripts/build_core.sh --fetch-headers
cc -shared -fPIC -O2 -I runtime/external/libretro-common/include \
   -o <core-id>_libretro.so <core-id>.c
```

The fetch step places `libretro.h` under `runtime/external/libretro-common/include`.
Use `clang -dynamiclib` and `.dylib` instead of `.so` on macOS, and `.dll` on
Windows. On Android and iOS, pass the target sysroot and architecture to the
NDK or Xcode compiler in the same shape. The `cc` line above is the Linux
example; the other platforms need their own compilers and sysroots.

### What the build script's flags mean

`build_core.sh` cannot be pointed at an arbitrary id: `<id>` is dispatched to
`build_<id>()`, and an id with no recipe fails with
`build_<id>: command not found`. It is still the reference for how each
platform is built, and these are the flags and variables it uses:

| Flag or variable | Effect |
|---|---|
| `--fetch-headers` | Shallow-clones libretro-common so the vendored `libretro.h` exists. Needs network once; `build_runtime.sh` refuses to run without it. |
| `<id>` | Runs `build_<id>()` in `scripts/build_core.sh`: clone upstream, make, stage. |
| `--tier1` | The five run-verified macOS cores. |
| `--tier-desktop` | The 17 shippable desktop cores; pair with `EZCORE_PLATFORM=linux` or `windows`. |
| `--tier-android` | The ten Android cores. |
| `--tier-ios` | The nine interpreter-only iOS cores. |
| `EZCORE_PLATFORM=macos\|linux\|windows\|android\|ios` | Selects the platform layer; defaults to `macos`, so set it for every other platform. |
| `EZCORE_ARCH` | Overrides the default architecture for the platform. |
| `EZCORE_OUT_DIR` | Overrides the staging root (`native/cores` on macOS arm64, `native/cores-<platform>-<arch>` otherwise). |
| `JOBS_OVERRIDE` | Parallel make jobs; defaults to the CPU count. |
| `EZCORE_NO_RESET=1` | Skips the source-tree reset between platform switches. For local iteration only, never for a pin or a release. |

For the repository's own cores the calls look like this; none of them builds a
core you wrote, because your id has no recipe:

```bash
scripts/build_core.sh --fetch-headers
EZCORE_PLATFORM=linux scripts/build_core.sh <id-with-a-recipe>
EZCORE_PLATFORM=linux scripts/build_core.sh --tier-desktop
EZCORE_PLATFORM=android scripts/build_core.sh --tier-android   # needs ANDROID_NDK_HOME
EZCORE_PLATFORM=ios scripts/build_core.sh --tier-ios           # macOS + Xcode, interpreter-only
```

The staging step strips debug symbols but keeps the exports used by `dlopen`,
writes `SHA256SUMS`, and ad-hoc signs the library on macOS; on iOS it also
repairs the link-time minimum OS version to 15.0. If you copy that staging
behaviour, pin the bytes after stripping and signing, not before.

The platform layer resolves the architecture, the library suffix, the manifest
pin key and the staging directory:

| Platform | `EZCORE_PLATFORM` | Default architecture | Pin key | Suffix | Staging directory |
|---|---|---|---|---|---|
| macOS | `macos` (default) | arm64 | `macos-arm64` | `.dylib` | `native/cores` |
| Linux | `linux` | x64 | `linux-x64` | `.so` | `native/cores-linux-x64` |
| Windows | `windows` | x64 | `windows-x64` | `.dll` | `native/cores-windows-x64` |
| Android | `android` | arm64-v8a | `android-arm64` | `.so` | `native/cores-android-arm64-v8a` |
| iOS | `ios` | arm64 | `ios-arm64` | `.dylib` | `native/cores-ios-arm64` |

`EZCORE_ARCH` overrides the architecture and `EZCORE_OUT_DIR` overrides the
staging root. Android builds need `ANDROID_NDK_HOME`; iOS builds need the Xcode
SDK and an explicit interpreter flag for any core whose default is a dynarec.

### How the app finds the library

Build the exact name: a library under any other name is reported as missing.
At install the library is found as `<core-id>_libretro.<ext>` first, then
`<core-id>.<ext>`, in the package root or in a `<core-id>/` subfolder. It is
then copied to `<local data>/cores/<core-id>/<core-id>.<ext>` with a `.ezpin`
sidecar for fast re-verification.

On every startup, discovery scans `<cores root>/<core-id>/`, accepts either
`<core-id>_libretro.<ext>` or `<core-id>.<ext>`, hashes the bytes and compares
them with `artifacts[<platform-arch>]` in the manifest before registering the
core. The platform key comes from the Dart `Abi` (`linux-x64`, `macos-arm64`,
`windows-x64`, `android-arm64`, `ios-arm64`); a manifest with no pin for the
running host is not launched. Bundled cores use the same `<id>/` shape in the
platform's bundled cores directory and are checked the same way.

For on-demand distribution the release asset name is
`<core-id>_libretro-<platform>-<arch>.<ext>`, as listed in `cores/release.json`.
Only assets listed there and in `cores/published-sha256.txt` are offered;
every other `download` core is reported as "not published yet" on that
platform.

## Installing a core from a file

On desktop or Android, open **Systems** and choose **Install core from file**.
Select the package folder, read the trust notice and confirm. The installer
then validates the manifest, finds the library for the current platform, checks
its SHA-256 against the pin, and copies it into the app's local data directory
under `cores/<core-id>/<core-id>.<ext>`. A missing pin, a hash mismatch or a
failed validation stages nothing.

Cores installed this way are labelled **Unverified**. The project has not
reviewed them, they never update themselves, and they run only because you chose
to install them. A core with `blocked_reason` is refused. A core with
`gated_reason` can be installed from your own build with a warning: the project
distributes its recipe only, and you are responsible for the rights to the
build. iOS does not support installing native code at runtime; its cores are
built into the app.

## Crash containment and the runtime host protocol

When the desktop **Crash protection** setting is on (it is off by default), the
app runs a session in a separate `ezcore_core_host` helper instead of in
process. Cores know nothing about this: they still speak libretro. The wire
contract is [`runtime/host/ezcore_core_host_protocol.h`](../runtime/host/ezcore_core_host_protocol.h).
It is an app-to-helper protocol — not a core ABI, not part of the package
format, and not something a core implements.

What it guarantees:

- Framing, in both directions, is a little-endian `u32` body length followed
  by that many bytes. A request body starts with a `u8` op, a response with a
  `u8` status (`EZH_OK` or `EZH_ERROR`); an error body is a UTF-8 message.
  Strings are a `u32` byte length plus UTF-8 bytes, blobs a `u32` length plus
  bytes. The protocol version is 1.
- The ops cover open (core, content, system and save directories, options),
  frame, pause, button/analog/mouse/key/pointer input, save, restore, cheats,
  reset, options/set-option and close. A save state is the largest message;
  the host refuses request bodies over 256 MiB (`EZH_MAX_REQUEST`).
- The helper exits 0 when its input reaches EOF, so it never outlives the app.
  `CLOSE` ends the session and the helper exits 0. A crash in the core kills
  the helper; the app sees EOF and reads the exit status to classify the
  crash. A helper that stops answering is killed by a watchdog and reported
  as hung, not crashed.
- With crash protection off, or where the helper is unavailable (it is not
  wired for Android and is forbidden on iOS), the session runs in-process and
  a native crash can still end the app.

The same framing is used by the generic engine host, which can run a
non-libretro engine when started with `--engine=NAME` (the default is libretro).
That is a host capability exercised by the runtime tests, not a package option;
neither host changes what a libretro core implements.

## Cores without save states

A libretro core may return 0 from `retro_serialize_size()`. That is a supported
case, not a malformed package: the library loads, initialises and runs
content. The runtime's `ezcore_serialize_size()` reports 0 when no state size
is available, and the app's save path fails explicitly with "Core does not
support save states" rather than writing an empty file. Automatic snapshots
are best-effort and silently skipped. Set `cheats_supported: false` if the
core has neither feature; no save-state data belongs in the package.

The verification matrix cannot promote such a core to **BOOTS** or **RENDERS**,
because those levels require a serialize/restore round trip. Its recorded
level stays **IDENTIFIES** even when frames are captured; those frames are
evidence of drawing only. See the PocketTick row in
[`MATRIX.md`](MATRIX.md) for the worked example. Do not claim a save or a
render for a core whose state round trip was never made.

## Licensing and the Core Module Exception

The app and runtime are GPL-3.0-only with the
[Core Module Exception](LICENSE-EXCEPTION.md). Under that exception an
independent core module may be under terms of your choice, including proprietary
terms, provided it communicates through libretro or the ezCORE package
interface, is distributed as a distinct module, and contains no ezCORE code.
The exception grants nothing over third-party code: a core that includes or
links emulator code must still follow that code's licence. A GPL-2.0-only core
cannot be bundled with the GPL-3.0-only app, and a non-commercial core is not
distributed in any project binary. The full policy is
[LICENSING.md](LICENSING.md).

Say that your core "works with ezCORE". Do not call it "ezCORE" or use the logo;
the name and brand are reserved ([TRADEMARKS.md](../TRADEMARKS.md)). Official
builds are published only by the maintainer and may contain proprietary
first-party cores that may not be extracted or redistributed.

## What is refused

- Cores with `blocked_reason` are legal holds. They are never built, pinned,
  shipped or installed. The 3DS and Switch slots are held under project policy.
- Cores with `gated_reason` build but have `delivery: absent` on every platform
  and are not distributed by the project.
- A package may not contain a ROM, BIOS, firmware, key, box art or commercial
  game title. Firmware fields name files; they never carry content.
- The app never compiles cores on the device.

## Platform constraints

- **iOS.** iOS does not allow loading third-party native code at runtime.
  Cores are built into the app, never downloaded and never installed from a
  folder. Execution on iOS is interpreter-only.
- **macOS.** Current releases are ad-hoc signed and are not notarised. If macOS
  blocks the app on first launch, right-click it and choose **Open**, or clear
  the quarantine flag with `xattr -cr /Applications/ezCore.app`.
- **Android and Google Play.** Cores ship bundled in the APK; the project
  publishes no separate Android core downloads. Only the maintainer may publish
  an app under the ezCORE name on Google Play or any other store, and official
  store builds may include proprietary first-party cores that may not be
  redistributed.
- **Desktop crash protection.** Running a core in a separate helper process is
  an experimental, opt-in setting on desktop. When it is off, or where the
  helper is unavailable, a native core crash can still end the app.

## Check your work

Before sharing a package, run the checks the repository uses:

```bash
flutter analyze
flutter test
python3 scripts/fill_manifest_data.py --check
python3 scripts/build_catalog.py
python3 scripts/license_audit.py
bash scripts/banned_content_scan.sh
```

Those gates inspect the repository, not a package built outside it. To check
that your own library loads, build the native boot harness from a checkout and
point it at the library in your package:

```bash
cmake -S runtime -B runtime/build-core-boot -DCMAKE_BUILD_TYPE=Release
cmake --build runtime/build-core-boot --target test_core_boot -j4
runtime/build-core-boot/test_core_boot <package-dir>/<core-id>_libretro.so --identify-only
```

It loads and initialises the library, prints the name the core reports through
`retro_get_system_info`, and exits non-zero if the library cannot be loaded or
initialised. Identify-only proves no more than that: the printed name is not
checked, and nothing here proves a frame, a save or correct behaviour
(see the IDENTIFIES limits in [`MATRIX.md`](MATRIX.md)).

The catalog check rejects an iOS `download` delivery, duplicate identifiers and
a blocked core that carries artifacts. The license and content gates refuse
non-commercial or incompatible licences and any prohibited file. A core that
compiles is not proof that it plays; per-system evidence is in
[MATRIX.md](MATRIX.md).
