# Contributing

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
