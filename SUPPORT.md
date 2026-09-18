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
- **Switch/3DS/PS2 cores** — legal holds, never built (see TRADEMARKS.md, CONTRIBUTING.md)
- **Commercial game compatibility claims** — we verify core boot/render, not game libraries
- **Proprietary cores** — only open-source libretro cores with compatible licenses
- **Private builds** — all releases are public on GitHub

## Frequently Asked Questions

### Installation & Setup
**Q: Where do I download ezCORE?**
A: [GitHub Releases](../../releases) — macOS (.zip), Windows (.zip), Linux (.tar.gz), Android (.apk)

**Q: macOS says "ezCore.app is damaged" or won't open**
A: The release is ad-hoc signed. Run: `xattr -cr /Applications/ezCore.app` then open. For notarized builds, we need an Apple Developer identity (see RELEASE_PLAN.md).

**Q: Android APK won't install**
A: Enable "Install unknown apps" for your browser/file manager. The APK is debug-signed; release signing requires a keystore.

### Emulation
**Q: My game won't load / black screen / crashes**
A: 
1. Check [MATRIX.md](docs/MATRIX.md) — is that core verified for your platform?
2. Verify you have required BIOS files (Systems screen shows exact filenames + hashes)
3. Try a different core for the same system (Library → Game Hub → Core Picker)
4. File a bug with logs if it should work

**Q: How do I add BIOS files?**
A: Systems screen → tap a core → "BIOS Required" row shows exact filenames. Place in the app's `bios/` folder (Settings → Library & Storage → Open Data Folder).

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
A: Read [CORE_SYSTEM.md](docs/CORE_SYSTEM.md) and [CONTRIBUTING.md](CONTRIBUTING.md). Core must be open-source libretro, compatible license, no legal exposure.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Hard rules (instant close)
- Normal rules (tests, analyze, DCO sign-off)
- Core version bump process
- Legal holds

## License

GPL-3.0-only for the app shell. Each core keeps its upstream license — see `cores/<id>/manifest.json`.