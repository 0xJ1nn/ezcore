# Support

## Getting Help

### Before Asking
1. **Read the docs** — start with [README.md](README.md), [ARCHITECTURE.md](docs/ARCHITECTURE.md), [MATRIX.md](docs/MATRIX.md)
2. **Search existing issues** — your question may already be answered
3. **Check the FAQ** below

### Support Channels

| Channel | Purpose | Response Time |
|---------|---------|---------------|
| **GitHub Issues** | Questions, bug reports and feature requests (use templates) | Triage within 7 days |
| **Security** | Vulnerabilities only — see [SECURITY.md](SECURITY.md) | 48h acknowledgment |

Privacy questions can be raised on the GitHub issues page as well; see
[PRIVACY.md](docs/PRIVACY.md) and [TERMS.md](docs/TERMS.md) first.

### What We Don't Support

- **ROM/BIOS/game file acquisition** — we ship zero copyrighted content. Bring your own dumps.
- **Switch/3DS cores** — holds, never built (see TRADEMARKS.md, CONTRIBUTING.md)
- **Commercial game compatibility claims** — we verify core boot/render, not game libraries
- **Proprietary cores** — only open-source libretro cores with compatible licenses
- **Private builds** — all releases are public on GitHub

## Frequently Asked Questions

### Installation & Setup
**Q: Where do I download ezCORE?**
A: The desktop builds are on [GitHub Releases](https://github.com/0xJ1nn/ezcore/releases): a signed and notarised download for macOS, an installer and a portable zip for Windows, and an AppImage and a tar.gz archive for Linux. The iOS and iPadOS builds come from the App Store and the Android build from Google Play; both listings are coming soon. Every official download is listed in the README, and checksums are published with each release.

**Q: macOS says "ezCore.app is damaged" or won't open**
A: The release is ad-hoc signed, not notarized. Run: `xattr -cr /Applications/ezCore.app` then open. (Notarized builds need an Apple Developer identity.)

**Q: Android APK won't install**
A: Enable "Install unknown apps" for your browser/file manager, and make sure any older ezCORE debug build is uninstalled first (debug and release signatures can't upgrade each other). Release APKs are signed with the project's release keystore.

**Q: How do desktop updates work?**
A: The Windows, Linux and macOS download builds check once a day for a newer release. When one is found, Settings › About offers the download and the release notes, and verifies the file against the published checksum before opening it. Turn the check off in Settings › About if you prefer. Store builds update through their store.

### Purchases

**Q: What is Diamond?**
A: An optional subscription in the App Store and Google Play builds that supports the project. It adds the Diamond badge and accent and the option to be named in the credits, and unlocks nothing: every feature and core is free for everyone. See [TERMS.md](docs/TERMS.md) for renewal, cancellation and refunds.

**Q: What are tips?**
A: One-time purchases that unlock nothing. Outside the stores, support goes through GitHub Sponsors. Purchases are handled by the stores; the app only reads the result on your device.

### Emulation
**Q: My game won't load / black screen / crashes**
A: 
1. Check [MATRIX.md](docs/MATRIX.md) — is that core verified for your platform?
2. Verify you have required BIOS files (Systems screen shows exact filenames + hashes)
3. Try a different core for the same system (Library → Game Hub → Core Picker)
4. File a bug with logs if it should work

**Q: How do I add BIOS files?**
A: Place them in the app's `system/` folder inside the app data directory — macOS: `~/Library/Application Support/ezcore/system/`, Windows: `%APPDATA%\ezcore\system\`, Linux: `~/.local/share/ezcore/system/`. The Systems screen and the player name the exact files a core is missing. (On Android the folder is app-private in v0.2.x — mobile placement is planned.) See [INSTALL.md](docs/INSTALL.md#bios--firmware).

**Q: Cheats don't work**
A: 
- Ensure the core supports cheats (check `cheats_supported` in manifest.json)
- Use the Cheats screen to add/import .cht files
- Some cheats require "reset on apply" (toggle in cheat editor)

### Saves & Vault
**Q: Where are my save states / SRAM?**
A: Time Capsule screen (vault) shows all snapshots. SRAM is per-game in the app's data directory.

**Q: Can I sync saves across devices?**
A: Not in v1. Local vault only. Cloud sync is planned.

### Development
**Q: How do I build from source?**
A: See [BUILDING.md](docs/BUILDING.md) — `scripts/prereqs.sh` → `scripts/build_runtime.sh` → `scripts/build_core.sh --tier1` → `flutter run`

**Q: How do I add a new core?**
A: Read [CORE_SYSTEM.md](docs/CORE_SYSTEM.md) and [CONTRIBUTING.md](CONTRIBUTING.md). Core must be open-source libretro, compatible license, no IP exposure.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Hard rules (instant close)
- Normal rules (tests, analyze, DCO sign-off)
- Core version bump process
- Holds

## License

GPL-3.0-only for the app shell. Each core keeps its upstream license — see `cores/<id>/manifest.json`.