# ezCORE brand files

Every brand file is generated from one set of shapes in
[`scripts/build_brand.py`](../scripts/build_brand.py): the twin-hexagon mark
(two halves of a gamepad, cut by one diagonal with blue light along it), the
"ez CORE" wordmark, the app icon and its variations. Never edit the outputs by
hand. Change the shapes and run:

```bash
python3 scripts/build_brand.py            # SVG + PNG + platform icons (needs rsvg-convert, ImageMagick)
python3 scripts/build_brand.py --svg-only # vectors and the app's Dart paths only
```

## Palette

| Swatch | Hex | Use |
|---|---|---|
| Ink | `#0A0A0A` | the mark on light backgrounds, the dark icon |
| Blue | `#007BFF` | the light along the cut, primary actions, the blue icon |
| Mist | `#DDE6F4` | text on dark |
| White | `#FFFFFF` | the mark on dark backgrounds |

Tagline: **Emulation shouldn't be hard.** Pillars: Simple · Powerful · Everywhere.

## Files (`assets/branding/`)

| File | What |
|---|---|
| `mark.svg`, `mark-white.svg` | the mark, solid (lockup style) |
| `mark-outline.svg` | the mark as rings (app-icon style) |
| `wordmark-dark.svg`, `wordmark-light.svg` | "ez CORE" |
| `lockup-dark.svg/.png`, `lockup-light.svg/.png` | mark + wordmark, for light / dark backgrounds |
| `app-icon.svg`, `app-icon-1024.png` | **the app icon**, used everywhere: the iPhone icon (dark tile, mark at 74%) with its continuous-corner rounding baked in |
| `app-icon-hero.svg`, `app-icon-hero-1024.png` | the brand sheet's hero tile: dark glass, blue rim light, silver mark and wordmark (presentation only, not a launcher icon) |
| `icon-dark`, `icon-light`, `icon-blue` (`.svg/.png`) | the three icon variations |
| `icon-ios.svg` | full-bleed tile for iOS (the system rounds it): the source of the app icon |
| `icon-macos.svg` | the app icon on Apple's macOS grid (824 px tile in 1024, drop shadow) |
| `icon-android-foreground.svg` | adaptive-icon foreground (108 dp canvas; the launcher masks the shape) |
| `social-preview.svg/.png` | 1280×640 repository card |
| `palette.svg/.png` | the four swatches |

Every launcher icon is the iPhone icon. iOS uses `icon-ios.svg` (the system
rounds it); Windows, Linux and legacy Android use `app-icon.svg` (same tile,
rounding baked in); Android 8+ gets an adaptive icon (gradient background +
`icon-android-foreground.svg`, also its themed monochrome layer); macOS uses
`icon-macos.svg`. The app draws the mark and wordmark from
`lib/brand/brand_paths.g.dart` (same geometry, generated), so the in-app logo
always matches these files. The few labels set in type (tagline, ™) use the
bundled Manrope.

The brand marks are the project's; see [`TRADEMARKS.md`](../TRADEMARKS.md).
