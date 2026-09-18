# ezCore UI Design Specification

> **Version:** 1.0
> **Date:** 2026-09-16
> **Status:** Draft
> **Design language:** Linear / Vercel / Stripe standard

---

## Overview

ezCore's UI is designed to be **fun, modern, and 3D** — not a generic emulator front-end. The interface feels like a premium product, with purposeful 3D elements that enhance the experience without being gimmicky.

---

## Design Principles

### 1. Purposeful 3D

3D is used to enhance the experience, not as a gimmick. Every 3D element serves a purpose — game shelves show depth when browsing, box art rotates for inspection, transitions between screens feel spatial.

### 2. Zero-Click Defaults

The UI works out of the box. Games appear in the library, cores download automatically, cheats are one tap away. Power users can tweak everything, but defaults are smart.

### 3. Retro-Modern Aesthetic

Retro game content meets modern UI design. Clean typography, generous spacing, subtle animations. Think "museum of retro gaming" rather than "90s shareware."

### 4. Delight in Details

Haptic feedback, smooth transitions, satisfying sound effects, micro-animations. Every interaction should feel intentional.

---

## Design Tokens

### Colors

```css
/* Light mode */
--background: #FAFAFA;
--surface: #FFFFFF;
--surface-raised: #F5F5F5;
--foreground: #1A1A1A;
--muted-foreground: #6B6B6B;
--border: #E5E5E5;
--accent: #6C5CE7;        /* Primary action */
--accent-soft: #E8E5FF;   /* Accent background */
--success: #00C853;
--warning: #FFB300;
--error: #FF5252;

/* Dark mode */
--background: #0F0F0F;
--surface: #1A1A1A;
--surface-raised: #242424;
--foreground: #FAFAFA;
--muted-foreground: #999999;
--border: #2A2A2A;
--accent: #8B7CFF;
--accent-soft: #2A2540;
```

### Typography

```css
--font-display: 'Gabarito', sans-serif;    /* Headings, numbers */
--font-body: 'Hanken Grotesk', sans-serif;  /* UI text */
--font-mono: 'JetBrains Mono', monospace;  /* Filenames, codes */
```

### Spacing

```css
--space-xs: 4px;
--space-sm: 8px;
--space-md: 16px;
--space-lg: 24px;
--space-xl: 32px;
--space-2xl: 48px;
```

### Radius

```css
--radius-sm: 6px;
--radius-md: 10px;
--radius-lg: 16px;
--radius-xl: 24px;
--radius-full: 9999px;  /* Pills, circles */
```

### Shadows

```css
--shadow-sm: 0 1px 2px rgba(0,0,0,0.05);
--shadow-md: 0 4px 12px rgba(0,0,0,0.1);
--shadow-lg: 0 8px 24px rgba(0,0,0,0.15);
--shadow-xl: 0 16px 48px rgba(0,0,0,0.2);
```

---

## Screen-by-Screen Design

### 1. Onboarding (First Launch)

**Goal:** Get from zero to playing in under 60 seconds.

```
┌──────────────────────────────────────────┐
│                                          │
│         ┌─────────────────────┐          │
│         │   3D rotating logo   │          │
│         │   (ezCore emblem)   │          │
│         └─────────────────────┘          │
│                                          │
│    "Welcome to ezCore"                   │
│    "Your games. Everywhere."             │
│                                          │
│         ┌─────────────────────┐          │
│         │   Sign in (OAuth)   │          │
│         └─────────────────────┘          │
│                                          │
│         ┌─────────────────────┐          │
│         │   Continue as guest │          │
│         └─────────────────────┘          │
│                                          │
│    [🗂 Drop ROMs to get started]        │
│                                          │
└──────────────────────────────────────────┘
```

- 3D logo rotates on hover/drag
- OAuth: Continue with Google / Continue with Apple
- Guest mode: local-only, no cloud saves
- Drop zone for ROMs (drag-and-drop)

### 2. Library (Home Screen)

**Goal:** Browse your collection beautifully, launch with one tap.

```
┌──────────────────────────────────────────┐
│  ← ezCore        🔍 Search    ⚙ Settings │
├──────────────────────────────────────────┤
│                                          │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐       │
│  │ 🎮  │ │ 🎮  │ │ 🎮  │ │ 🎮  │  ← 3D │
│  │ NES │ │ SNES│ │ GBA │ │ PS1 │  shelf │
│  └─────┘ └─────┘ └─────┘ └─────┘       │
│                                          │
│  ── Continue Playing ──                  │
│  ┌────────────────────────────────┐     │
│  │ [box art] Super Mario Bros.  ▶ │     │
│  │           2h 15m ago           │     │
│  └────────────────────────────────┘     │
│                                          │
│  ── Recent ──                            │
│  ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐   │
│  │[box] │ │[box] │ │[box] │ │[box] │   │
│  │Zelda │ │Metroid│ │Pokemon│ │Castle│   │
│  └──────┘ └──────┘ └──────┘ └──────┘   │
│                                          │
└──────────────────────────────────────────┘
```

**Features:**
- System shelf: 3D shelf showing games by system, with depth and parallax
- Continue Playing: horizontal card strip, auto-surfaced based on last-played
- Recent: grid of recently played games
- Search: instant fuzzy search by title
- Filter: by system, favorite, has cheats, etc.
- Sort: alphabetical, last played, play time, rating

**Interactions:**
- Tap game card → Game detail (3D box rotation)
- Long press → Context menu (play, edit, cheats, delete)
- Drag to reorder (guest mode)
- Pull to refresh (re-scan library)
- Swipe right on Continue Playing card → Launch game

### 3. Game Detail

**Goal:** Showcase the game, provide quick actions.

```
┌──────────────────────────────────────────┐
│  ← Back                                  │
├──────────────────────────────────────────┤
│                                          │
│    ┌──────────────────────────┐         │
│    │                          │         │
│    │   [3D Rotating Box Art]  │         │
│    │                          │         │
│    └──────────────────────────┘         │
│                                          │
│              Super Mario Bros.           │
│              NES · 1985 · Platformer     │
│                                          │
│    ⭐ 4.8   🕐 12h 30m   🏆 68%         │
│    ♥ Filled  🔖 Tagged  📝 Has cheats   │
│                                          │
│    ┌────────────────────────────────┐   │
│    │          ▶ PLAY                │   │
│    └────────────────────────────────┘   │
│                                          │
│    ── Saves ──                           │
│    ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ │
│    │Slot0 │ │Slot1 │ │Slot2 │ │ +Add │ │
│    │[img]  │ │[img]  │ │[img]  │ │      │ │
│    └──────┘ └──────┘ └──────┘ └──────┘ │
│                                          │
│    ── Cheats (12 found) ──               │
│    ☑ Infinite Lives                      │
│    ☑ Invincibility                       │
│    ☐ Moon Jump                           │
│    ☐ Start with Fire Flower              │
│    [View All]                            │
│                                          │
└──────────────────────────────────────────┘
```

**Features:**
- 3D box art rotates on drag, gyroscope (mobile)
- Screenshot carousel below box art
- Quick actions: Play, Favorite, Tag, Share
- Save slots with thumbnailcreenshots, tap to load, long press to delete
- Cheats: toggle switches, grouped by category
- Metadata: rating, play time, last played, genre

**Interactions:**
- Tap Play → Launch game in player screen
- Tap save slot → Load save state
- Tap cheat toggle → Enable/disable cheat
- Swipe screenshots → Navigate carousel
- 3D box art → Drag to rotate, pinch to zoom

### 4. Player Screen

**Goal:** Immersive gameplay with accessible controls.

```
┌──────────────────────────────────────────┐
│                                          │
│           ┌──────────────────┐           │
│           │                  │           │
│           │   [Emulator      │           │
│           │    Screen]       │           │
│           │   60 FPS         │           │
│           │                  │           │
│           └──────────────────┘           │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │  ≡  Save  Load  FF  Rewind  Pause │ │
│  └────────────────────────────────────┘ │
│                                          │
│  [Touch controls if mobile]              │
│  ┌─────┐                    ┌─────┐     │
│  │ D-Pad│                    │ A B │     │
│  │  ➕  │                    │  X Y│     │
│  └─────┘                    └─────┘     │
│                                          │
└──────────────────────────────────────────┘
```

**Features:**
- Fullscreen game screen (Aspect ratio preserved, letterboxed)
- Overlay controls: minimal, auto-hide after 3s
- Quick actions: Save, Load, Fast Forward, Rewind, Pause
- Haptic feedback on button press
- Screenshot button (captures + shares)
- Performance overlay: optional FPS, frame time
- Shader selector: CRT, Scanline, Pixel Perfect, None

**Interactions:**
- Tap screen → Show/hide controls
- Swipe down → Show controls
- Swipe up → Show controls
- Two-finger tap → Screenshot
- Long press → Quick save
- Controller: any button → Action

**Player Controls:**
- Save state: `Select + R1` or on-screen `💾 Save`
- Load state: `Select + L1` or on-screen `📂 Load`
- Fast forward: `Hold R2` or on-screen `⏩ FF`
- Rewind: `Hold L2` or on-screen `⏪ Rewind`
- Pause: `Select + Start` or on-screen `⏸ Pause`
- Screenshot: `Select + X` or on-screen `📸`

### 5. Cheat Browser

**Goal:** Find and enable cheats easily.

```
┌──────────────────────────────────────────┐
│  ← Cheats: Super Mario Bros.             │
├──────────────────────────────────────────┤
│  🔍 Search cheats...                     │
├──────────────────────────────────────────┤
│                                          │
│  ── All (24) ──                          │
│                                          │
│  ☑ Infinite Lives                        │
│    GameShark: C2E9-0001                  │
│                                          │
│  ☑ Invincibility                         │
│    GameShark: A2B1-0002                  │
│                                          │
│  ☐ Moon Jump                             │
│    GameShark: 3D6E-0003                  │
│                                          │
│  ☐ Start with Fire Flower                │
│    GameShark: 9F1A-0004                  │
│                                          │
│  ☐ Unlimited Coins                       │
│    GameShark: B2C3-0005                  │
│                                          │
│  [Import Cheat File]                     │
│                                          │
└──────────────────────────────────────────┘
```

**Features:**
- Search/filter cheats by name
- Toggle enable/disable
- Show cheat code (GameShark/Action Replay format)
- Import .cht files
- Category grouping (Gameplay, Items, Power-ups, etc.)
- Shows game the cheats apply to

**Interactions:**
- Tap cheat → Toggle enable/disable
- Long press → Show details
- Search bar → Filter
- Import button → File picker

### 6. Settings

**Goal:** Comprehensive but organized.

```
┌──────────────────────────────────────────┐
│  ← Settings                              │
├──────────────────────────────────────────┤
│                                          │
│  ── Account ──                           │
│  👤 RetroGamer                           │
│  ✉️ user@example.com                    │
│  👑 Upgrade to Pro                      │
│                                          │
│  ── Library ──                           │
│  📁 ROM folders            [Manage]      │
│  🔄 Auto-scan on launch     [On]         │
│  ☁️ Enable cloud sync       [On/Pro]      │
│  🖼 Fetch metadata           [On]         │
│                                          │
│  ── Player ──                            │
│  🎮 Default shader           [CRT]       │
│  📐 Aspect ratio             [Fit]       │
│  🔊 Volume                   [80%]       │
│  📳 Haptics                  [On]         │
│  ⚡ Rewind buffer           [30s]        │
│  🎬 Fast forward speed     [2x]         │
│  🎹 Controller mapping        [Manage]    │
│                                          │
│  ── Cores ──                             │
│  📦 Manage cores           [6 installed] │
│  🔄 Check for updates hourly [On]          │
│                                          │
│  ── Advanced ──                          │
│  🖥 Show FPS                [Off]        │
│  🐛 Debug logging          [Off]         │
│  📋 Export diagnostics      [Export]     │
│                                          │
│  ── About ──                             │
│  🏷 ezCore v1.0.0                        │
│  📜 Open source (GPL-3.0)               │
│  🔗 GitHub repo                          │
│                                          │
└──────────────────────────────────────────┘
```

---

## 3D Rendering Approach

### Option A: Flutter 3D (Experimental)

- Built into Flutter
- Good for simple 3D scenes
- Limited ecosystem

### Option B: Custom Shaders (Recommended)

- Fragment shaders for 3D effects
- Good performance
- Full control

### Option C: 3D Engine (Bevy, Unity)

- Most powerful
- Most complex
- Harder to integrate with Flutter

**Recommendation:** Option B (custom shaders) for v1, evaluate Option A (Flutter 3D) for v2.

### 3D Effects

| Effect | Technique | Performance |
|---|---|---|
| Game shelf depth | Layered parallax | Low |
| Box art rotation | Fragment shader | Medium |
| Screen transitions | Animated transform | Low |
| Particle background | Instanced rendering | Medium |

---

## Animation Principles

- **Buttery smooth:** 60 FPS target for all animations
- **Subtle:** Animations enhance, not distract
- **Fast:** Transitions under 300ms
- **Spring:** Physics-based spring animations for natural feel
- **Stagger:** List items animate in sequence (stagger)

### Durations

| Animation | Duration |
|---|---|
| Screen transition | 200-300ms |
| Button press | 100ms |
| List item appear | 200ms |
| 3D rotation | 150ms |
| Tooltip | 150ms |

---

## Themes

### Included Themes

| Theme | Description | 3D Included |
|---|---|---|
| **Porcelain** (default)/light | Clean, bright, minimal | Basic |
| **Ink** (default) dark | Dark, focused, immersive | Basic |
| **Retro Neon** | 80s arcade vibes | Full |
| **Cyberpunk** | Futuristic, glowing | Full |
| **Minimal** | Flat, no 3D | None |
| **Wood Shelf** | Classic collector | Full |

### Theme Features

- Color tokens (dark and light variants)
- 3D effect preset
- Sound effect pack
- Custom font (optional)

---

## Responsive Design

| Breakpoint | Width | Layout Changes |
|---|---|---|
| Mobile | < 600px | Single column, touch controls |
| Tablet | 600-900px | Two column, touch+mouse |
| Desktop | > 900px | Multi-column, hover states |

### Platform-Specific

- **Mobile:** Bottom sheet menus, thumb-friendly controls
- **Tablet:** Side-by-side layouts, drag-and-drop
- **Desktop:** Keyboard shortcuts, right-click menus, hover tooltips

---

## Accessibility

- Full keyboard navigation (desktop)
- Screen reader labels
- High contrast option
- Reduced motion option
- Scalable text
- Focus indicators on all interactive elements
