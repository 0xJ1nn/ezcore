# ezCore Modular Core System

> **Version:** 1.0
> **Date:** 2026-09-16
> **Status:** Draft

---

## Overview

ezCore uses a **modular core architecture** — each emulation system is a separate binary (libretro core) that is downloaded, loaded, and updated independently of the main app. This is the foundation of ezCore's legal safety, size efficiency, and community extensibility.

---

## Why Modular?

| Benefit | Explanation |
|---|---|
| **Legal safety** | Cores are separate binaries, not linked into ezCore. No copyrighted code in the main app. |
| **Size** | Users only download cores for systems they play. Base app stays small. |
| **Community** | Third-party developers can build cores without touching ezCore. |
| **Updates** | Update cores independently of the main app. |
| **Licensing** | Each core can have its own license. |

---

## Core Structure

Each core is a self-contained package:

```
cores/<id>/
├── manifest.json          # Core metadata, version, supported systems
├── libretro_core.so       # The actual libretro core (platform-specific)
├── sha256.txt             # Integrity hash
└── README.md              # Core-specific notes
```

### Directory Layout

```
cores/
├── mesen/
│   ├── manifest.json
│   ├── libretro_core.so
│   ├── sha256.txt
│   └── README.md
├── snes9x/
│   ├── manifest.json
│   ├── libretro_core.so
│   ├── sha256.txt
│   └── README.md
├── mgba/
│   ├── manifest.json
│   ├── libretro_core.so
│   ├── sha256.txt
│   └── README.md
└── ...
```

---

## Manifest Schema (v1)

```json
{
  "id": "mesen",
  "name": "Mesen",
  "version": "0.9.9",
  "systems": ["nes"],
  "author": "SourMesen",
  "license": "GPL-3.0",
  "abi_version": 1,
  "execution": {
    "windows": "dynarec",
    "macos": "dynarec",
    "linux": "dynarec",
    "android": "dynarec",
    "ios": "interpreter"
  },
  "sha256": {
    "windows-x64": "abc123...",
    "macos-arm64": "def456...",
    "linux-x64": "ghi789...",
    "android-arm64": "jkl012...",
    "ios-arm64": "mno345..."
  },
  "download_url": "https://github.com/ezcore/cores/releases/download/v1.0/mesen-{platform}.zip"
}
```

### Manifest Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | ✅ | Unique core identifier (lowercase, no spaces) |
| `name` | string | ✅ | Display name |
| `version` | string | ✅ | Core version (semver) |
| `systems` | string[] | ✅ | Supported system IDs (e.g., `["nes"]`) |
| `author` | string | ✅ | Core author/organization |
| `license` | string | ✅ | SPDX license identifier |
| `abi_version` | int | ✅ | Libretro ABI version (must be 1) |
| `execution` | object | ✅ | Per-OS execution mode (`dynarec` or `interpreter`) |
| `sha256` | object | ✅ | Per-platform SHA-256 hashes |
| `download_url` | string | ✅ | Download URL template (`{platform}` placeholder) |

### Execution Modes

| Mode | Description | iOS Allowed? |
|---|---|---|
| `dynarec` | Dynamic recompilation (JIT) — fastest | ❌ No |
| `interpreter` | Interpreted execution — slower but safe | ✅ Yes |
| `unknown` | Not declared — treated as interpreter | ✅ Yes |

**iOS rule:** iOS must never resolve to `dynarec`. The manifest validation enforces this. If a core declares `dynarec` for iOS, the manifest is rejected.

---

## Core Loading Flow

```
1. User selects a game
       ↓
2. ezCore checks CoreRegistry for compatible cores
       ↓
3. If no core installed → prompt to download
       ↓
4. Download core package (zip) from download_url
       ↓
5. Verify sha256
       ↓
6. Extract to cores/<id>/
       ↓
7. dlopen the core (RTLD_NOW | RTLD_LOCAL)
       ↓
8. Verify ABI version (must be 1)
       ↓
9. Resolve libretro symbols
       ↓
10. Set environment, video, audio, input callbacks
       ↓
11. Load game
       ↓
12. Ready to play
```

### Loading States

| State | Description |
|---|---|
| `not_installed` | Core not downloaded |
| `downloading` | Core package being downloaded |
| `verifying` | SHA-256 verification in progress |
| `extracting` | Zip extraction in progress |
| `loading` | dlopen in progress |
| `ready` | Core loaded and ready |
| `error` | Loading failed (see error message) |

---

## Core Registry

The core registry is a local database that tracks installed cores:

```dart
class CoreRegistry {
  // Returns all installed cores
  List<CoreManifest> get installedCores;

  // Returns cores compatible with a system
  List<CoreManifest> compatibleCores(String systemId);

  // Returns the default core for a system
  CoreManifest? defaultCore(String systemId);

  // Installs a core from a downloaded package
  Future<void> installCore(Uint8List packageBytes);

  // Removes an installed core
  Future<void> removeCore(String coreId);

  // Updates an installed core
  Future<void> updateCore(String coreId);
}
```

---

## Core Sandboxing

Cores run in the **same process** (libretro requirement) but are isolated:

| Isolation | Mechanism |
|---|---|
| **Symbol isolation** | `RTLD_LOCAL` — core symbols don't leak |
| **File system** | Restricted to system/save directories |
| **Network** | Blocked (cores don't need internet) |
| **Memory** | Core can't access ezCore memory (separate heap) |

---

## Supported Systems

### Tier 1 (Launch)

| System | Core | Status |
|---|---|---|
| NES | Mesen | ✅ Verified |
| SNES | Snes9x | ✅ Verified |
| Game Boy | mGBA | ✅ Verified |
| Game Boy Color | mGBA | ✅ Verified |
| Game Boy Advance | mGBA | ✅ Verified |
| Genesis/Mega Drive | Genesis Plus GX | ✅ Verified |

### Tier 2 (v1.1)

| System | Core | Status |
|---|---|---|
| Nintendo 64 | Mupen64Plus | ✅ Verified |
| PlayStation 1 | PCSX-ReARMed | ✅ Verified |
| PSP | PPSSPP | ✅ Verified |
| Nintendo DS | DeSmuME | ✅ Verified |

### Tier 3 (v1.2)

| System | Core | Status |
|---|---|---|
| Arcade | FBNeo | 📝 Planned |
| Neo Geo | FBNeo | 📝 Planned |
| TurboGrafx-16 | Mednafen | 📝 Planned |

### Tier 4 (v2.0)

| System | Core | Status |
|---|---|---|
| Saturn | Yabause | 📝 Planned |
| Dreamcast | Flycast | 📝 Planned |

### Never (Legal Holds)

| System | Reason |
|---|---|
| Switch | Nintendo litigation (2024 Yuzu settlement) |
| 3DS | Nintendo litigation |
| PS2 | Sony litigation risk |

---

## Core Distribution

### Download Sources

**GitHub Releases** (locked in — ADR-004).

- Primary distribution: GitHub Releases (free, versioned, community-friendly)
- ezCore downloads cores on demand from the Releases page
- Users can also manually drop cores into the `cores/` directory
- Each release is tagged with core ID + platform (e.g., `mesen-macos-arm64.zip`)
- SHA-256 hashes published alongside release artifacts

### Catalog Loading

The app loads the core catalog from `cores/catalog.json` — a single merged file containing all manifests. This avoids Flutter asset bundling issues with subdirectory traversal.

```dart
// app_state.dart
final catalogRaw = await rootBundle.loadString('cores/catalog.json');
final catalog = json.decode(catalogRaw) as Map<String, dynamic>;
for (final entry in catalog.entries) {
  manifests[entry.key] = json.encode(entry.value);
}
registry.loadCatalog(manifests);
```

**Why:** Flutter's asset bundler doesn't reliably copy `cores/<id>/` subdirectories into the app bundle. A single JSON file loads reliably.

### Download URL Template

```
https://github.com/ezcore/cores/releases/download/v{version}/{id}-{platform}.zip
```

Example:
```
https://github.com/ezcore/cores/releases/download/v1.0/mesen-macos-arm64.zip
```

### Platform Identifiers

| Platform | Identifier |
|---|---|
| Windows x64 | `windows-x64` |
| macOS arm64 | `macos-arm64` |
| macOS x64 | `macos-x64` |
| Linux x64 | `linux-x64` |
| Android arm64 | `android-arm64` |
| iOS arm64 | `ios-arm64` |

---

## Core Updates

Cores are updated independently of the main app:

1. ezCore periodically checks for core updates (manifest version comparison)
2. User is prompted to update
3. New core package is downloaded and verified
4. Old core is replaced
5. Games using the core continue to work (ABI is stable)

---

## Community Cores

The modular design enables third-party core development:

1. Developer builds a libretro core for any system
2. Creates a manifest.json
3. Publishes to GitHub (or any hosting)
4. Users add the core to their `cores/` directory
5. ezCore loads it like any built-in core

### Core Submission Guidelines

- Must implement libretro API v1
- Must include valid manifest.json
- Must provide sha256 hashes for all platforms
- Must not require proprietary firmware
- Must not be for Switch/3DS/PS2 (legal holds)

---

## Security

### SHA-256 Verification

Every core package is verified before extraction:

```cpp
bool verifyCorePackage(const std::string& path, const std::string& expectedHash) {
    // Compute SHA-256 of the package
    std::string actualHash = computeSHA256(path);
    return actualHash == expectedHash;
}
```

### Manifest Validation

The manifest is validated before the core is loaded:

- `id` must be unique
- `abi_version` must be 1
- `execution.ios` must not be `dynarec`
- `sha256` must contain an entry for the current platform
- `download_url` must be a valid URL

### dlopen Safety

```cpp
void* handle = dlopen(corePath, RTLD_NOW | RTLD_LOCAL);
if (!handle) {
    // Core couldn't be loaded — reject
    return nullptr;
}
// RTLD_LOCAL ensures symbols don't leak into the global namespace
```

---

## Future: Core Store

A built-in core store (v2.0) would allow:

- Browse available cores
- One-click install
- Automatic updates
- Community ratings
- Core screenshots and descriptions

This is a future enhancement, not a launch requirement.
