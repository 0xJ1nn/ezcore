# ezCORE Core Matrix State

> Snapshot date: 2026-09-23 (PS2 entries refreshed 2026-10-18)
> Canonical evidence and refresh procedure:
> [`../docs/MATRIX.md`](../docs/MATRIX.md).
> This file is a compact development-memory view. It does not promote a build
> or load result to gameplay verification.

## Legend

- **B** — built/pinned evidence exists for the stated platform.
- **I** — core identifies/loads in the native harness.
- **R** — content boots, produces frames, and the stated save/restore check
  passes.
- **—** — not verified for that platform.
- **N/A** — not applicable or deliberately absent.
- **Recipe** — build recipe exists, but the upstream license prevents binary
  distribution.
- **Hold** — reserved manifest; never built or shipped.

Controller, save, shader, and cheat columns describe the current application
contract, not independent per-core gameplay proof. The runtime supports
optional save-state symbols and normalized button input; most cores have not
been individually exercised for every feature.

## Core inventory

| Core | System(s) | Upstream / license | Delivery | macOS | Linux | Windows | Android | iOS | Saves | Controllers | Shaders | Cheats | BIOS | Gameplay / notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| PocketBit | GB/GBC | SameBoy / MIT | bundled | R | B | — | B | — | ABI seam; per-core round trip not isolated | normalized input | — | yes | none | Blargg fixture render evidence; broader game verification pending |
| Gambatte | GB/GBC | Gambatte / GPL-2.0-only | Recipe/policy-only in current releases | R | — | — | B | — | ABI seam; not isolated | normalized input | — | yes | none | Compatibility/licensing gate; not a current binary distribution |
| AdvanceBit | GBA/GB/GBC | mGBA / MPL-2.0 | bundled | R | B | — | B | N/A | ABI seam; save path wired | normalized + touch | — | yes | none | Controller/integration fixture evidence exists; device run pending |
| NesByte | NES/FDS | Mesen / GPL-3.0 | bundled | I | B | — | B | — | ABI seam; Mesen quirk isolated | normalized input | — | yes | FDS optional | Identify/load evidence; broad gameplay not verified |
| SuperFX | SNES | Snes9x / non-commercial custom | Recipe | I | — | — | B | — | ABI seam; not isolated | normalized input | — | yes | none | Non-commercial recipe only; no binary distribution |
| BlastProc | Genesis/SMS/GG | Genesis Plus GX / non-commercial custom | Recipe | I | — | — | B | — | ABI seam; not isolated | normalized input | — | yes | optional | Non-commercial recipe only; no binary distribution |
| Joystick | Atari 2600 | Stella / GPL-2.0-or-later | bundled | I | B | — | B | — | ABI seam; not isolated | normalized input | — | yes | none | Identify evidence; gameplay not verified |
| CardCon | PC Engine/TG-16 | Beetle PCE Fast / GPL-2.0-or-later | bundled | I | B | — | B | — | ABI seam; not isolated | normalized input | — | yes | optional | Identify evidence; disc formats need content verification |
| RealMode | DOS | DOSBox Pure / GPL-2.0-or-later | bundled | I | B | — | B | — | ABI seam; not isolated | normalized input | — | yes | none | Identify evidence; no gameplay claim |
| CoinBox | Arcade/Neo Geo | FBNeo / non-commercial custom | Recipe | I | — | — | B | — | ABI seam; not isolated | normalized input | — | yes | user files | Non-commercial recipe only; no binary distribution |
| PointClick | SCUMM/adventure | ScummVM / GPL-3.0 | desktop download; Android/iOS bundled | I | I/B | — | B | — | ABI seam; not isolated | normalized input | — | no | none | Large desktop artifact; download path unit-tested, not device-verified |
| Geometry1 | PlayStation | SwanStation / GPL-3.0 | bundled | I | B | — | N/A | N/A | ABI seam; not isolated | normalized input | — | yes | optional/required by title | GL/default-renderer caveat; frame evidence incomplete |
| RCP64 | N64 | Mupen64Plus-Next / GPL-2.0-or-later | bundled | I | B | — | N/A | N/A | ABI seam; not isolated | normalized input | — | yes | none | Linux ABI evidence; software-renderer/core-options caveat |
| DualScreen | Nintendo DS | melonDS / GPL-3.0 | bundled | I | B | — | N/A | N/A | ABI seam; not isolated | normalized input | — | yes | required | Software-renderer/core-options caveat |
| PortComp | PSP | PPSSPP / GPL-2.0-or-later | bundled | I | B | — | N/A | N/A | ABI seam; not isolated | normalized input | — | yes | none | GL/default-renderer caveat; gameplay unverified |
| DreamArc | Dreamcast/NAOMI | Flycast / GPL-2.0-or-later | desktop download; mobile absent | I | B | — | N/A | N/A | ABI seam; not isolated | normalized input | — | yes | required | Large download core; release-asset evidence platform-specific |
| PowerCube | GameCube/Wii | Dolphin / GPL-2.0-or-later | desktop download; mobile absent | I | B | — | N/A | N/A | ABI seam; not isolated | normalized input | — | yes | optional | No verified software-renderer path in current matrix |
| TwinSH | Saturn | Beetle Saturn / GPL-2.0-or-later | bundled | I | B | — | N/A | N/A | ABI seam; not isolated | normalized input | — | yes | required | Slow interpreter; gameplay unverified |
| LRPS2 | PlayStation 2 | PCSX2 (libretro port) / GPL-3.0-or-later | bundled (Linux x64 only) | — | R | — | — | — | ABI seam; not isolated | normalized input | — | no | required (user dump) | Linux x64 RENDERS on homebrew with a user-supplied BIOS (2026-10-07); other platforms absent |
| DualVU | PlayStation 2 | Play! / BSD-2-Clause | bundled (Linux x64 only) | — | R | — | — | — | ABI seam; not isolated | normalized input | — | no | none (HLE) | BIOS-free HLE kernel; Linux x64 RENDERS on CC0 homebrew, restore exact (2026-10-18) |
| 3DS hold (`citra_hold`) | 3DS | Reserved / no build | Hold | — | — | — | — | — | N/A | N/A | — | no | N/A | Never build or ship pending IP/licensing review |
| Switch hold (`switch_hold`) | Switch | Reserved / no build | Hold | — | — | — | — | — | N/A | N/A | — | no | N/A | Never build or ship pending IP/licensing review |

## Matrix interpretation

- The catalog contains 20 active core manifests plus 2 explicit hold slots.
- An em dash in the iOS column means the current committed manifest has no
  iOS artifact pin; older release notes may contain historical build claims.
- “Bundled,” “download,” “recipe,” and “absent” are distribution policy, not
  proof that a core is playable.
- A pin proves artifact identity, not accuracy or gameplay compatibility.
- Per-core boot tests must remain fork-isolated because native cores run
  in-process and can crash the test process.
- Before changing a row, rebuild or run the relevant test and update the
  canonical matrix with the exact command, platform, and limitation.
