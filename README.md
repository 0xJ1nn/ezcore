# Universal Emulator (working title — rebrand pending)

Open-source multi-system emulator frontend for macOS, Windows, iOS, Android.
Pluggable libretro cores you can install, update, and remove. Full cheat
support. Zero bundled games, BIOS, keys, or cheat databases.

## Bring your own dumps

This app plays **only** files you supply yourself (plus bundled
public-domain homebrew samples used as test fixtures). It ships no ROMs,
BIOS/firmware, decryption keys, game art, or cheat databases, and links to
none. See `TRADEMARKS.md`, `DMCA.md`, `CONTRIBUTING.md`.

## Layout

- `lib/` — Flutter shell (library, core manager, player, cheats, settings)
- `cores/<id>/manifest.json` + `cores/registry.json` — signed plugin index (21 entries: 18 real, 3 legal holds)
- `bridge/` — Libretro C bridge (`libretro_bridge.h`, ABI v1) loaded over FFI
- `scripts/build_core.sh` — reproducible core builds into `native/cores/<id>/`
- `test/` — `flutter test` (17 tests, green)

## Quick start (macOS dev)

```bash
scripts/build_core.sh --fetch-headers   # vendor libretro.h
scripts/build_core.sh --tier1           # build verified cores
flutter analyze && flutter test         # gates
flutter run -d macos                    # run shell
```

Core artifacts are verified (sha256 vs manifest pin) before `dlopen`.
iOS cores are bundled at build time only — never downloaded (App Review 2.5.2/4.7).

## Systems at launch scope

GB/GBC (SameBoy, Gambatte) · GBA (mGBA) · NES (Mesen) · SNES (Snes9x) ·
Genesis/SMS/GG (Genesis Plus GX) · Atari 2600 (Stella) · DOS (DOSBox Pure) ·
TG-16 (Beetle PCE) · PS1 (SwanStation) · N64 (Mupen64Plus) · DS (melonDS) ·
PSP (PPSSPP) · Dreamcast (Flycast) · GameCube/Wii (Dolphin, desktop/Android) ·
Saturn (Beetle Saturn) · Arcade (FBNeo, gated) · ScummVM.

**Legal holds (reserved slots, never built):** 3DS, Switch, PS2.
Reasons live in `cores/*_hold/manifest.json`. In short: Citra/Yuzu fell to
Nintendo's 2024 anti-circumvention actions, and no shippable open PS2
libretro core exists. This protects the project and its users.

## License

App shell: GPL-3.0-only (`LICENSE`). Each core keeps its upstream license —
see `cores/<id>/manifest.json` (`license`, `license_url`).
