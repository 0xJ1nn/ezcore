---
title: ezCORE — Product Vision
version: 1.0.0
updated: 2026-09-15
---

# ezCORE — The Open-Source Universal Game Emulation Platform

## One beautiful unified platform. Many modular emulator cores.

ezCORE is not simply an emulator frontend. It is the open-source universal game emulation platform — a single, highly-polished surface under which dozens of emulator implementations disappear behind a clean, modular architecture.

The user provides their own games and system files. ezCORE provides everything else: the library, the player, the tools, and the polish.

**ezCORE = platform / orchestration / frontend**
**Cores = modular emulator implementations**

## Core Philosophy

### Game → Play
A normal user opens ezCORE, finds a game, presses Play, and it runs. They never touch a core selector, a renderer dropdown, a BIOS prompt, or a shader chain unless they choose to.

A power user can go as deep as they want: Game → Core → Renderer → Shader → Controller → Cheats → Save State → Performance. Both workflows coexist. Progressive disclosure is not a feature — it is the architecture.

### One Library. One Surface. Many Systems.
The user has **one** game library. ezCORE handles the complexity underneath. The frontend is never tightly coupled to any single emulator implementation. New platforms are added by installing a core — the application does not require a redesign.

### Modular Core Architecture
Cores are versioned plugins, signed and SHA-pinned, each declaring what systems it supports, what file extensions it opens, what cheat families it exposes, and what execution strategy it uses per platform. A core that satisfies the runtime ABI works on every platform unchanged.

### Licensing and Technical Separation
ezCORE ships no copyrighted game content, BIOS/firmware, decryption keys, proprietary Nintendo assets, or cheat databases, and links to none. The UX clearly separates ezCORE software (which we build) from user-provided content (which the user owns).

For newer or proprietary platforms (3DS, Switch, PS2), the architecture reserves slots and supports modular third-party integrations while keeping ezCORE itself cleanly separated from proprietary system software. Holds are enforced at the manifest level, not as an afterthought.

## Product Identity

### Visual Language
- **Futuristic but usable** — premium gaming platform, not a sci-fi movie UI
- **Highly polished** — every pixel considered, every transition intentional
- **Modular** — visual blocks that snap together, reflecting the architecture
- **Playful** — joy in motion, satisfying micro-interactions, never dour
- **Powerful** — depth available but not threatening
- **Highly customizable** — themes, layouts, densities, card styles
- **Approachable for beginners** — clear hierarchy, gentle onboarding, no jargon
- **Deep enough for power users** — advanced panels, per-game overrides, debug surfaces
- **Console-agnostic / Platform-agnostic** — no single brand dominates
- **Modern 3D interface** — spatial where it helps, flat where it doesn't
- **Smooth animations** — purposeful motion language, never flashy for spectacle

### What ezCORE Feels Like
- "I have ONE game library, and ezCORE handles the complexity underneath."
- Not RetroArch with a new skin
- Not a generic emulator launcher
- Not every screen a flat settings panel
- **ezCORE has its own unmistakable visual identity**

## Supported Platform Strategy

### Launch Scope
GB/GBC · GBA · NES · SNES · Genesis/SMS/GG · Atari 2600 · DOS · TG-16 · PS1 · N64 · DS · PSP · Dreamcast · GameCube/Wii (desktop/Android) · Saturn · Arcade · ScummVM

### Future / Holds
3DS, Switch, PS2 — reserved slots. Architecture supports them; IP clearance gates actual implementation.

### Dynamic Platform Registry
The UI does not hardcode a console menu. New platforms appear dynamically as cores are installed. Today's scope is not tomorrow's ceiling.

## Major Product Surfaces

### Onboarding
First launch · Platform discovery · Core setup · Game library import · Controller setup · Optional cloud configuration · Privacy & content-provenance explanation

### Home
Recently played · Continue playing · Favorites · Recently added · Recommendations based on user's own library · Installed cores · Quick actions

### Universal Game Library
All games · Platform filters · Genre filters · Favorites · Recently played · Search · Sorting · Grid/List/3D views

### 3D Game Library (Spatial Browsing)
Console shelves · 3D game cards · Floating collections · Console "worlds" · Galaxy/spatial library · cinematic game discovery — 3D used where it improves navigation, discovery, platform identity, and immersion; never forced.

### Game Detail
Artwork · Screenshots · Description · Platform · Play · Save states · Achievements · Cheats · Controller profile · Performance profile · Core information · Settings

### Game Launch / Play Experience
Launch animation · Loading · Quick menu · Pause overlay · Save state · Load state · Screenshot · Recording · Cheats · Controller settings · Performance settings

### Core Manager
Installed cores · Available cores · Updates · Compatibility · Core details · Permissions/licensing information

### Core Discovery / Installation
Browse compatible cores for your library; install with one tap; SHA-pinned and verified before load.

### Controller Center
Controller detection · Button mapping · Profiles · Per-console layouts · Per-game overrides · Touch controls · Vibration · Motion controls

### Touch Controls
Customizable virtual buttons · Layouts · Opacity · Size · Skins · Presets · Per-game configuration

### Save Center
Saves · Save states · Backups · Cloud synchronization · Restore/version history

### Cheat Center
Cheats per game · Enable/disable · Presets · Search · Safe UX (validated, no databases shipped)

### Performance Center
FPS · Frame pacing · Renderer · Resolution · Shaders · Latency · Performance profiles · Automatic optimization

### Themes / Skins
Complete themes · UI skins · Game card styles · Controller skins · Community themes

### Settings
Powerful but not overwhelming — progressive disclosure.

### Profile / Account
Local profile · Optional account · Cloud sync · Preferences · Library statistics

### Search
Universal — across games, platforms, cores, settings, collections.

### Core/Platform Compatibility
Visually understandable: Game → Platform → Compatible Core(s) → Recommended Core → Launch

### Empty States
Designed carefully: "No PS2 games yet → Add your own game files" / "No compatible core installed → Explore available cores"

### Error / Recovery States
Missing system file · Incompatible core · Corrupted save · Unsupported format · Controller disconnected · Cloud sync conflict

### Licensing / User-Supplied Content UX
Neutral, professional, non-preachy language: "Bring your own game files" / "ezCORE manages your collection and provides the tools to play it."

## Architecture (from UI perspective)

```
Flutter UI  →  C ABI / FFI  →  ezCore Runtime  →  modular cores
```

- Cores never touch Flutter
- Runtime owns execution: lifecycle, AV, saves, cheats, quirks
- Platform execution strategy lives in data (per-core manifest), not code
- Save bytes are opaque to the frontend
- Game → Play: library resolves game to core; first compatible installed core auto-selected

## Cross-Platform Strategy
Windows · Linux · macOS · Android · iOS/iPadOS · Steam Deck / handheld PC · TV/controller-first environments

Every important flow supports: Mouse · Keyboard · Gamepad · Touch — where appropriate.

## Animation Language
- Game card transitions
- Console transitions
- Page transitions
- Launch sequence
- Modal transitions
- Save-state feedback
- Core installation
- Controller connection
- Library scanning
- Cloud synchronization

Animations feel intentional and premium — not flashy for the sake of being flashy.

## Design System
- Display font + body font
- Spacing scale
- Cards · Buttons · Navigation · Icons
- Glass/material treatment
- Depth · Shadows · Borders · Gradients
- 3D surfaces
- Motion · Transitions · Hover states · Focus states
- Controller navigation · Touch interaction
- Accessibility
- Dark/light themes

## 3D Design Principle
3D should not exist merely because it looks cool. Use 3D where it improves:
- Navigation
- Discovery
- Platform identity
- Game browsing
- Spatial organization
- Transitions
- Immersion

Keep important utility screens fast, readable, and efficient. The design language balances: **Cinematic + Functional + Fast**. Do not sacrifice usability for spectacle.

## Long-Term Roadmap Themes

> The authoritative, status-tracked plan is [`ROADMAP.md`](ROADMAP.md) — see
> its **Platform program** for delivery order and gates. The binding platform
> contract is [`docs/PLATFORM.md`](docs/PLATFORM.md). The themes below express
> *direction*; where they conflict with either of those, those win.

1. **Universal Modular Core System** — any core satisfying the libretro ABI
   works everywhere, added by anyone, without forking the app
2. **Core Packages** — the emulator plus its touch controls, skin, cheats, and
   functions as one validated, installable unit
3. **Trust & Safety Tiers** — reviewed *ezCORE Verified* cores labelled as
   such; self-serve cores opt-in, labelled, and never auto-updated
4. **Crash Containment** — a faulty core never takes down the application
5. **Cloud Saves & Sync** — iCloud / OneDrive / account sync via swappable `SaveSyncProvider`
6. **Achievements** — per-game, per-core
7. **Netplay** — where cores expose it
8. **Screenshots / Recording / Replay** — instant capture, instant share
9. **Core Discovery & Update System** — one-tap install, one-tap update, SHA-pinned
10. **AI-Assisted Optimization** — automatic per-game performance tuning
11. **Community Themes & Skin System** — user-generated visual identity
12. **3D Spatial Library** — cinematic discovery for users who want it
13. **Handheld / TV / Desktop Adaptive Shells** — same platform, different form factors
14. **Current-Generation & PC-Game Targets** — supervised engines driven through
    the shell, scoped honestly as supervision rather than embedding

## What This Document Is
This is a **product vision and design principles** document. It establishes **product direction**, not implementation details. It belongs in the project root and governs the Moonboard, the design system, and the architecture.

The **engineering** counterpart is [`docs/PLATFORM.md`](docs/PLATFORM.md): what
the platform is, the core/runtime/UI boundary, the package format, the security
model, and the invariants that may not be broken.

## What This Document Is Not
- It is not a technical spec for any given core
- It is not a substitute for TRADEMARKS.md or DMCA.md
- It is not an API reference (see docs/ARCHITECTURE.md)
- It is not an engineering contract (see docs/PLATFORM.md)
- It is not a feature roadmap with dates (see ROADMAP.md)
- It is not a build guide (see README.md)
