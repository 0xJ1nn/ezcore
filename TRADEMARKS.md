# Trademark & Brand Policy

## Third-Party Console Trademarks

This project is not affiliated with, sponsored, or endorsed by Nintendo, Sony, Sega, Atari, or any game publisher. All console and game titles belong to their owners.

Rules for contributors and the app itself:
- Never use console brand names or logos in the app name, icon, or marketing copy. Describe compatibility functionally ("GB-compatible core", "plays your GBA dumps").
- Never bundle game art, box scans, or trademarked screenshots. Store listings show homebrew titles only.
- System labels in the UI use neutral short codes (`gb`, `snes`, …); the human-readable mapping in-app avoids brand styling.

---

## ezCORE Brand Protection

**The ezCORE name, logo, icon, lockups, and brand identity are reserved trademarks.**

| What's Protected | Status |
|------------------|--------|
| "ezCORE" word mark | ™ Reserved |
| App icon (blue hexagon + "ez") | ™ Reserved |
| Lockups (horizontal/vertical) | ™ Reserved |
| "Game → Play" tagline | ™ Reserved |
| Orbit console UI design language | © Copyright |

### What This Means

**You MAY (under GPL-3.0):**
- Fork the source code
- Modify and build your own version
- Distribute your modified binaries
- Use the core build system for your own projects
- Contribute changes back upstream

**You MAY NOT (without explicit written permission):**
- Publish apps to any store (Play Store, App Store, Microsoft Store, etc.) under the name "ezCORE" or confusingly similar names
- Use the ezCORE app icon, lockups, or brand assets in your builds
- Represent your fork as the official ezCORE release
- Use the ezCORE brand in marketing, screenshots, or store listings
- Redistribute the official release artifacts unchanged but rebranded

### For Store Distribution

Only the official maintainer (JinUltimate1995) may publish ezCORE to:
- Google Play Store
- Apple App Store / TestFlight
- Microsoft Store
- GitHub Releases (official)
- Any other software distribution platform

Forks must:
1. Use a different app name (e.g., "MyEmu", "RetroCore", etc.)
2. Use different icons/branding (assets/branding/ is NOT licensed for reuse)
3. Update `applicationId` / bundle ID / package name
4. Remove or replace all ezCORE brand references in UI strings
5. Clearly state "Based on ezCORE" in about screen (not "ezCORE")

### Enforcement

Unauthorized store publications will be reported to the platform for trademark infringement. The GPL-3.0 license on the code does not grant trademark rights.

### Requesting Permission

Official distribution partnerships or co-branding: open a GitHub Discussion or email the maintainer.

---

## License Summary

| Component | License | Notes |
|-----------|---------|-------|
| App shell (Flutter/Dart) | GPL-3.0-only | Full source freedom |
| ezCore Runtime (C) | GPL-3.0-only | Full source freedom |
| Core manifests/scripts | GPL-3.0-only | Full source freedom |
| Fonts (Space Grotesk, Manrope) | SIL OFL 1.1 | Bundled, can redistribute |
| Brand assets (icon, lockups) | **All Rights Reserved** | NOT open license |
| Upstream libretro cores | Their respective licenses | See `cores/<id>/manifest.json` |