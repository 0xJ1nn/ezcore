# Installation Guide

## Quick Start

Download the latest release for your platform from [GitHub Releases](../../releases/latest).

### macOS (Apple Silicon)
1. Download `ezcore-<version>-macos-arm64.zip`
2. Unzip: `unzip ezcore-<version>-macos-arm64.zip`
3. Move `ezCore.app` to `/Applications`
4. **First launch**: macOS will block it (ad-hoc signed). Fix:
   ```bash
   xattr -cr /Applications/ezCore.app
   ```
   Then open from Applications folder.

### Windows (x64)
1. Download `ezcore-<version>-windows-x64.zip`
2. Extract to a folder (e.g., `C:\ezCore\`)
3. Run `ezCore.exe` from that folder

### Linux (x64)
1. Download `ezcore-<version>-linux-x64.tar.gz`
2. Extract: `tar -xzf ezcore-<version>-linux-x64.tar.gz`
3. Run: `./ezCore` from the extracted `bundle/` directory

### Android (arm64)
1. Download `ezcore-<version>-android-arm64.apk`
2. Enable "Install unknown apps" for your browser/file manager
3. Open the APK to install
4. **Note**: Debug-signed APK. For Play Store, a release-signed AAB is needed.

## Requirements

| Platform | Minimum |
|----------|---------|
| macOS | 12.0 (Monterey), Apple Silicon or Intel |
| Windows | Windows 10 1903+, x64 |
| Linux | glibc 2.31+, x64, GTK 3, ALSA |
| Android | API 24 (Android 7.0), arm64-v8a |
| iOS | 15.0+, arm64 (TestFlight only, not on GitHub) |

## First Run

1. **Welcome screen** — tap "Get Started"
2. **Import games** — tap "+" or use the Import screen:
   - Pick a folder containing your ROMs (you own these)
   - ezCORE scans recursively, identifies games by hash
   - Generates deterministic covers for each game
3. **Play** — tap a game in Library, then "Play" in the Game Hub

## BIOS / Firmware

Some systems require BIOS files you must provide:

| System | Core | Required Files |
|--------|------|----------------|
| PC Engine CD | beetle_pce | `syscard3.pce` |
| Saturn | beetle_saturn | `sega_101.bin`, `mpr-17933.bin` |
| PlayStation | swanstation | `scph5500.bin` / `scph5501.bin` / `scph5502.bin` (optional — OpenBIOS fallback) |
| Dreamcast | flycast | `dc_boot.bin`, `dc_flash.bin` |
| DS | melonds | `bios7.bin`, `bios9.bin`, `firmware.bin` |
| Arcade/NeoGeo | fbneo | `neogeo.zip` + per-board BIOS |

Place BIOS files in the app's `bios/` folder (Settings → Library & Storage → Open Data Folder). The Systems screen shows exact filenames and SHA-256 hashes.

## Legal Notice

**ezCORE ships zero copyrighted content.** No ROMs, BIOS, firmware, keys, game art, or cheat databases are included or linked. You must provide your own legally obtained game dumps and BIOS files.

See [TRADEMARKS.md](TRADEMARKS.md), [DMCA.md](DMCA.md), [CONTRIBUTING.md](CONTRIBUTING.md).

## Troubleshooting

### macOS: "App is damaged / can't be opened"
```bash
xattr -cr /Applications/ezCore.app
# Or if that fails:
codesign --force --deep --sign - /Applications/ezCore.app
```

### Linux: Missing libraries
```bash
# Ubuntu/Debian
sudo apt install libgtk-3-0 libglib2.0-0 libalsa2
# Arch
sudo pacman -S gtk3 glib2 alsa-lib
# Fedora
sudo dnf install gtk3 glib2 alsa-lib
```

### Android: "App not installed"
- Check architecture: must be arm64 device (most 2018+ phones)
- Free storage: need ~200MB for app + cores + games
- Clear previous install: Settings → Apps → ezCORE → Uninstall

### No games found on import
- Ensure folder contains supported extensions (`.gb`, `.gbc`, `.gba`, `.sfc`, `.smc`, `.nes`, `.md`, `.bin`, `.iso`, `.cue`, etc.)
- Check Systems screen → core → "Extensions" for full list
- Subfolders are scanned recursively

## Updating

Download the new release and replace the app. Your games, saves, and settings are stored in the app's data directory and are **not** affected by app updates.

## Uninstalling

| Platform | Method |
|----------|--------|
| macOS | Delete `/Applications/ezCore.app` + `~/Library/Application Support/ezCore/` (optional) |
| Windows | Delete the extract folder + `%APPDATA%\ezCore\` (optional) |
| Linux | Delete the extract folder + `~/.local/share/ezCore/` (optional) |
| Android | Settings → Apps → ezCORE → Uninstall |

## Support

- [GitHub Discussions](../../discussions) — questions, help, ideas
- [GitHub Issues](../../issues) — bugs, feature requests (use templates)
- [SUPPORT.md](SUPPORT.md) — detailed FAQ