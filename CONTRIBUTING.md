# Contributing

> How to contribute to ezCORE: the hard rules, how cores are added, licensing,
> the CLA, and AI-assisted contributions. Architecture lives in
> [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

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

Every contribution is covered by the [ezCORE CLA](CLA.md). Sign it once on
your first pull request, and sign off every commit (DCO): `git commit -s`.
The full licence map is [`docs/LICENSING.md`](docs/LICENSING.md).

In short:

1. You keep the copyright in your work. The CLA is a **licence, not an
   assignment**.
2. Your contribution is published under the repository's licence: GPL-3.0-only
   with the [Core Module Exception](LICENSE-EXCEPTION.md).
3. You also allow the maintainer to offer it under other terms. That is what
   lets official builds meet app-store terms and ship first-party cores.
4. In return, the maintainer **promises** that the open-source version stays
   available, and that the open-source version is never made less capable in
   order to sell a paid one (CLA §3).

If you contribute on behalf of an employer, make sure you have permission to
agree to these terms.

## AI-assisted contributions

AI tools are welcome. Undisclosed AI output is not.

- **Disclose it.** Any commit containing AI-generated code or text carries an
  `Assisted-by: <tool>` or `Co-Authored-By: <tool>` trailer. A pull request
  that is mostly AI-written says so in its description.
- **Author it as yourself.** Commits use your own real identity, never a
  placeholder such as `agent@local`. The pre-commit hook rejects placeholder
  identities. You are the author, and you are responsible for what you
  submit.
- **Review it as yourself.** You have read and understood every line, and you
  have no reason to think it reproduces third-party code (CLA §5.4). "The
  model wrote it" is not a provenance record.
- **No automatic merges.** Agent-generated pull requests are never merged into
  a release branch without human review.
