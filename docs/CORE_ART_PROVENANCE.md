# Core catalog artwork provenance

## Creation record

- **Created for:** ezCORE core catalog and Systems presentation
- **Creation date:** September 2026
- **Maintainer statement (2026-09-25):** the artwork was created for ezCORE by Codex using ChatGPT Images.
- **Source record:** no external artwork URL, uploaded source asset, or third-party asset library was supplied for these files.
- **Project use:** the files are distributed as part of the GPL-3.0-only ezCORE application. They are intended as generic catalog illustrations, not game covers or copied product branding.

## Rights basis and limits

The [OpenAI Terms of Use](https://openai.com/policies/row-terms-of-use/),
effective 2026-01-01, state that, as between the user and OpenAI and to the
extent permitted by applicable law, the user owns Output and OpenAI assigns
its rights in that Output to the user. The same terms warn that generated
content may be similar to other output and may reference third-party rights.

This repository record documents the maintainer's provenance statement and the
service terms used for the creation decision. It is not legal advice and does
not claim that generated output is unique or free of every third-party right.
Any future replacement or externally sourced artwork must receive its own
provenance and license record before distribution.

The machine-readable record, including the exact file set and SHA-256 pins, is
[`CORE_ART_PROVENANCE.json`](CORE_ART_PROVENANCE.json). The maintainer reviewed
all files on 2026-09-25 for visible logos, copied branding, and unacceptable
hardware trade-dress resemblance, and approved their redistribution in ezCORE.

## Files

| File | Catalog role |
|---|---|
| `advancebit.webp` | AdvanceBit / GBA family |
| `blastproc.webp` | BlastProc / 16-bit console family |
| `cardcon.webp` | CardCon / PCE family |
| `coinbox.webp` | CoinBox / arcade family |
| `dreamarc.webp` | DreamArc / disc-console family |
| `dualscreen.webp` | DualScreen / dual-screen family |
| `gambatte.webp` | Gambatte / GBC family |
| `generic.webp` | Unknown-system fallback |
| `geometry1.webp` | Geometry1 / PlayStation-family target |
| `joystick.webp` | Joystick / Atari 2600 family |
| `nesbyte.webp` | NesByte / NES family |
| `pocketbit.webp` | PocketBit / Game Boy family |
| `pointclick.webp` | PointClick / adventure-computer family |
| `portcomp.webp` | PortComp / handheld family |
| `powercube.webp` | PowerCube / GameCube-family target |
| `rcp64.webp` | RCP64 / Nintendo 64 family |
| `realmode.webp` | RealMode / home-computer family |
| `superfx.webp` | SuperFX / SNES family |
| `twinsh.webp` | TwinSH / Saturn family |

`scripts/license_audit.py` fails if any file is added to `assets/core_art/`
without being a flat WebP listed in this record. Nested directories, symlinks,
and non-WebP files are rejected because Flutter would otherwise bundle them
without a provenance entry.
