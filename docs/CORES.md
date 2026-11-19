# Cores and upstream projects

ezCORE packages emulators; it does not write them. Every core below is an
independent build of an open-source project, delivered through the
[libretro](https://www.libretro.com/) API. Each core keeps its own upstream
licence, and the source link points to the project it was built from. The
accompanying names, licences and links are provided for attribution; ezCORE
is not affiliated with, endorsed by, or supported by any upstream project.

Official builds may also include first-party cores that are not open source.
Those ship as compiled binaries only, are added at build time, and are never
committed to this repository. Their source is not published.

| Core | Upstream project | Source | Licence | Systems |
|---|---|---|---|---|
| AdvanceBit | mGBA | [libretro/mgba](https://github.com/libretro/mgba) | MPL-2.0 | GBA, GB, GBC |
| BlastProc | Genesis Plus GX | [libretro/Genesis-Plus-GX](https://github.com/libretro/Genesis-Plus-GX) | Genesis Plus GX custom (non-commercial) | Genesis, SMS, Game Gear, Sega CD |
| CardCon | Beetle PCE Fast | [libretro/beetle-pce-fast-libretro](https://github.com/libretro/beetle-pce-fast-libretro) | GPL-2.0-or-later | PC Engine, TurboGrafx-16, PC Engine CD |
| CoinBox | FBNeo | [libretro/FBNeo](https://github.com/libretro/FBNeo) | FBNeo custom (non-commercial) | Arcade, Neo Geo |
| DreamArc | Flycast | [flyinghead/flycast](https://github.com/flyinghead/flycast) | GPL-2.0-or-later | Dreamcast, NAOMI |
| DualScreen | melonDS | [libretro/melonDS](https://github.com/libretro/melonDS) | GPL-3.0 | Nintendo DS |
| DualVU | Play! | [jpd002/Play-](https://github.com/jpd002/Play-) | BSD-2-Clause | PlayStation 2 (BIOS-free path) |
| Gambatte | Gambatte | [libretro/gambatte-libretro](https://github.com/libretro/gambatte-libretro) | GPL-2.0-only | GB, GBC |
| Geometry1 | SwanStation | [libretro/swanstation](https://github.com/libretro/swanstation) | GPL-3.0 | PlayStation |
| Joystick | Stella | [libretro/stella2023](https://github.com/libretro/stella2023) | GPL-2.0-or-later | Atari 2600 |
| LRPS2 | LRPS2 (PCSX2) | [libretro/ps2](https://github.com/libretro/ps2) | GPL-3.0-or-later | PlayStation 2 |
| NesByte | Mesen | [libretro/Mesen](https://github.com/libretro/Mesen) | GPL-3.0 | NES, Famicom, FDS |
| PocketBit | SameBoy | [libretro/SameBoy](https://github.com/libretro/SameBoy) (from [LIJI32/SameBoy](https://github.com/LIJI32/SameBoy)) | MIT | GB, GBC |
| PointClick | ScummVM | [scummvm/scummvm](https://github.com/scummvm/scummvm) | GPL-3.0 | SCUMM adventures |
| PortComp | PPSSPP | [hrydgard/ppsspp](https://github.com/hrydgard/ppsspp) | GPL-2.0-or-later | PlayStation Portable |
| PowerCube | Dolphin | [libretro/dolphin](https://github.com/libretro/dolphin) | GPL-2.0-or-later | GameCube, Wii |
| RCP64 | Mupen64Plus-Next | [libretro/mupen64plus-libretro-nx](https://github.com/libretro/mupen64plus-libretro-nx) | GPL-2.0-or-later | Nintendo 64 |
| RealMode | DOSBox Pure | [libretro/dosbox-pure](https://github.com/libretro/dosbox-pure) | GPL-2.0-or-later | DOS |
| SuperFX | Snes9x | [libretro/snes9x](https://github.com/libretro/snes9x) | Snes9x custom (non-commercial) | Super Nintendo |
| TwinSH | Beetle Saturn | [libretro/beetle-saturn-libretro](https://github.com/libretro/beetle-saturn-libretro) | GPL-2.0-or-later | Sega Saturn |

BlastProc, CoinBox, SuperFX and Gambatte have upstream terms that do not
permit redistribution in an official build. Recipes for them are kept for
users who build their own cores; they are not shipped as binaries. Nintendo
3DS and Nintendo Switch are reserved slots only — no core is built or
distributed for either system.

Core availability per platform, including which cores are bundled and which
can be downloaded on demand, is recorded in [`MATRIX.md`](MATRIX.md). Licence
terms and per-file checks are in [`LICENSING.md`](LICENSING.md) and
[`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md).
