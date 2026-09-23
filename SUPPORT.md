# Support

## Getting Help

### Before Asking
1. **Read the docs** — start with [README.md](README.md), [ARCHITECTURE.md](docs/ARCHITECTURE.md), [MATRIX.md](docs/MATRIX.md)
2. **Search existing issues** — your question may already be answered
3. **Check the FAQ** below

### Support Channels

| Channel | Purpose | Response Time |
|---------|---------|---------------|
| **GitHub Discussions** | Questions, ideas, community help | Community-driven |
| **GitHub Issues** | Bug reports, feature requests (use templates) | Triage within 7 days |
| **Security** | Vulnerabilities only — see [SECURITY.md](SECURITY.md) | 48h acknowledgment |

### What We Don't Support

- **ROM/BIOS/game file acquisition** — we ship zero copyrighted content. Bring your own dumps.
- **Switch/3DS/PS2 cores** — holds, never built (see TRADEMARKS.md, CONTRIBUTING.md)
- **Commercial game compatibility claims** — we verify core boot/render, not game libraries
- **Proprietary cores** — only open-source libretro cores with compatible licenses
- **Private builds** — all releases are public on GitHub

## Frequently Asked Questions

### Installation & Setup
**Q: Where do I download ezCORE?**
A: [GitHub Releases](https://github.com/JinUltimate1995/ezcore/releases) — the current `v0.2.0` release attaches Linux x64 and Android arm64 artifacts; exact assets and verification are listed in the [release notes](.github/release-notes/v0.2.0.md) and [`docs/MATRIX.md`](docs/MATRIX.md). macOS, Windows, and iOS artifacts are not distributed in that release.

**Q: macOS says "ezCore.app is damaged" or won't open**
A: The release is ad-hoc signed, not notarized. Run: `xattr -cr /Applications/ezCore.app` then open. (Notarized builds need an Apple Developer identity — see RELEASE_PLAN.md.)

**Q: Android APK won't install**
A: Enable "Install unknown apps" for your browser/file manager, and make sure any older ezCORE debug build is uninstalled first (debug and release signatures can't upgrade each other). Release APKs are signed with the project's release keystore.

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
A: Not in v1. Local vault only. Cloud sync planned for v1.1 (see CLOUD_SAVES.md).

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