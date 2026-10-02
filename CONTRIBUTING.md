# Contributing

> **Canonical engineering rules:** [`project.md`](project.md) defines the full
> ezCORE development system — read it before contributing. This file covers
> contribution-specific policy (licensing, DCO); everything else lives
> in `project.md`.

## Hard rules (instant close, no discussion)

1. **No ROMs, BIOS/firmware, keys, or game files in PRs.** Any PR adding
   `*.gb *.gba *.sfc *.nds *.iso *.chd *.bin(bios) prod.keys title.keys`
   or similar is closed on sight.
2. **No cheat databases.** Cheat *engine* code and hand-written format
   samples only. Point to the opt-in community source instead of vendoring it.
3. **No circumvention tooling.** No key derivation, DRM bypass, CDN
   downloaders, sigpatches, or decrypters.
4. **No Nintendo/Sony/Sega marks** in code, assets, or copy. Say
   "GB-compatible core", never the console's brand name in titles/icons.
5. **No Switch/3DS core PRs.** The holds in `cores/*_hold/` stand until IP
   counsel clears them.

## Adding an emulator core to ezCORE

ezCORE is a platform: the intent is that a core is added **without forking the
application**. There are two supported ways in, and both are validated by the
same rules.

| Path | Who it is for | What happens |
|---|---|---|
| **Self-serve package** | Anyone, including you, right now | A core package — the emulator plus its control layout, skin, cheats, and functions — is placed locally or added from a published release. No account, no network required. |
| **Reviewed pull request** | Contributors who want the core shipped and labelled | A PR adds `cores/<id>/` with a manifest, license and provenance, and a build recipe. It must pass the manifest, license, and pin gates before it can be labelled **ezCORE Verified**. |

The detailed contract is [`docs/PLATFORM.md`](docs/PLATFORM.md) and the
decisions behind it are [`docs/DECISIONS.md`](docs/DECISIONS.md)
(ADR-014 … ADR-017). Read it before designing a core or a package.

### What a core must implement

**The libretro API v1.** A core exports `retro_*` entry points and reports
`RETRO_API_VERSION == 1`. It does **not** implement, call, or link against the
`ezcore_*` host API in `runtime/include/ezcore_runtime.h` — that surface belongs
to the application. See ADR-014.

Please do not design a new ezCORE-specific core interface. Using the existing
libretro contract is what makes an independent core usable by ezCORE, by
RetroArch, and by others.

A core must never depend on Flutter, on the Orbit UI, or on any application
type. It is a native artifact described by data.

### What a core must not do

- Require a specific core name, version string, or vendor to be special-cased by
  the application or the kernel. The runtime already carries exactly one such
  workaround (`runtime/src/runtime.c:272-287`); adding more is a last resort that
  needs an ADR explaining why.
- Execute anything from a package's data files. Control layouts, skins, cheats,
  and presets are JSON, and they never execute code.
- Assume a network connection, an account, or a remote service.

### Metadata and licensing

Reuse the standards that already exist rather than inventing parallel formats —
libretro `.info` files for core metadata, the existing `.cht` format for cheats,
and the existing `cores/<id>/manifest.json` schema, which stays valid as a
v1 package. Only control layouts, skins, and function hooks are ezCORE-specific.

Record provenance and license for every core. `scripts/license_audit.py` and
`scripts/verify_core_art.py` are enforced by the pre-commit hook; run them
before opening a PR. A GPL-2.0-only core cannot be bundled with the
GPL-3.0-only application — see the `gated_reason` on `cores/gambatte` for a
worked example of how a licensing problem is recorded honestly.

## Normal rules

- New code ships with a failing-first test (`flutter test` / `ctest`).
- `flutter analyze` must report no issues.
- Core version bumps must update `cores/<id>/manifest.json` + SHA pin and
  pass a homebrew boot test on at least one platform.
- Sign off commits (DCO): `git commit -s`.

## Licensing of contributions

By submitting a pull request you agree that:

1. The contribution is your own original work, or you have the right to
   submit it under these terms.
2. It is licensed to the project under **GPL-3.0-only** (inbound =
   outbound), and you keep all rights to your own work.
3. You grant 0xJ1nn a perpetual, worldwide, non-exclusive,
   royalty-free right to **relicense** your contribution under any
   OSI-approved license, and to use it in official builds distributed
   through any channel (including app stores).

Why point 3 exists: the project bundles third-party emulator cores whose
licenses differ per core, and some distribution channels (app stores) have
terms that conflict with copyleft. Without a relicensing grant, a single
GPL-only contribution could permanently block the project from adapting.
This is a license grant, **not a copyright assignment** — your
contribution stays yours.

If you are contributing on behalf of an employer, make sure you have
permission to agree to these terms.
