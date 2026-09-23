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
3. You grant JinUltimate1995 a perpetual, worldwide, non-exclusive,
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
