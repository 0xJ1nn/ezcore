#!/usr/bin/env python3
"""Build every ezCORE brand file from one set of shapes.

The brand sheet (twin-hexagon mark, "ez CORE" wordmark, app icon, icon
variations, palette) is redrawn here as geometry, so each file is an exact
vector and the app draws the very same shapes:

  assets/branding/*.svg          vector sources (mark, wordmark, lockups, icons)
  assets/branding/*.png          renders of those (needs rsvg-convert)
  lib/brand/brand_paths.g.dart   the same paths for the in-app painter
  platform launcher icons        android / ios / macos / windows / linux

Usage:  python3 scripts/build_brand.py            # everything
        python3 scripts/build_brand.py --svg-only # no rsvg-convert / magick

Never edit the outputs by hand; change the shapes here and re-run.
"""
from __future__ import annotations

import math
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "branding")

# ---- Palette (the sheet's four swatches) ----
INK = "#0A0A0A"
BLUE = "#007BFF"
MIST = "#DDE6F4"
WHITE = "#FFFFFF"

# ---- Shape language ----
# A path is a list of ops: ("M", x, y) ("L", x, y) ("Q", cx, cy, x, y)
# ("A", r, large, sweep, x, y) ("Z",). Every shape is drawn even-odd, so a
# hole is just a second closed contour inside the first.


def rounded_polygon(pts, r):
    """Closed polygon with every corner rounded by a quadratic of size r."""
    ops = []
    n = len(pts)
    for i in range(n):
        p0, p1, p2 = pts[i - 1], pts[i], pts[(i + 1) % n]

        def toward(a, b):
            dx, dy = b[0] - a[0], b[1] - a[1]
            d = math.hypot(dx, dy)
            k = min(r / d, 0.5)
            return (a[0] + dx * k, a[1] + dy * k)

        a, b = toward(p1, p0), toward(p1, p2)
        ops.append(("M" if i == 0 else "L", *a))
        ops.append(("Q", *p1, *b))
    ops.append(("Z",))
    return ops


def circle(cx, cy, r):
    return [("M", cx + r, cy), ("A", r, 0, 1, cx - r, cy),
            ("A", r, 0, 1, cx + r, cy), ("Z",)]


def translate(ops, dx, dy):
    out = []
    for op in ops:
        k = op[0]
        if k in ("M", "L"):
            out.append((k, op[1] + dx, op[2] + dy))
        elif k == "Q":
            out.append((k, op[1] + dx, op[2] + dy, op[3] + dx, op[4] + dy))
        elif k == "A":
            out.append((k, op[1], op[2], op[3], op[4] + dx, op[5] + dy))
        else:
            out.append(op)
    return out


# ---- The mark: two hexagon halves of a gamepad, cut by one diagonal ----
MARK_H = 200.0
SLANT = 120.0      # how far the cut leans across the full height
TIP = 68.0         # depth of the pointed outer ends
HALF_W = 287.0     # width of one half
GAP = 24.0         # the cut, where the blue light runs
# The right half is the left half turned 180 degrees and slid along the cut
# by GAP, which makes the whole mark 2*HALF_W - SLANT + GAP wide.
MARK_W = 2 * HALF_W - SLANT + GAP  # 478
CORNER = 16.0

LEFT = [(0, 100), (TIP, 0), (HALF_W - SLANT, 0), (HALF_W, MARK_H), (TIP, MARK_H)]
RIGHT = [(MARK_W - x, MARK_H - y) for (x, y) in LEFT]

DPAD_C = (120.0, 100.0)
DPAD_ARM = 44.0
DPAD_T = 15.0
DOTS_C = (MARK_W - 120.0, 100.0)
DOT_OFF = 28.0
DOT_R = 15.0

# The light along the cut: centre line of the gap.
CUT_TOP = (HALF_W - SLANT + GAP / 2, 0.0)
CUT_BOTTOM = (HALF_W + GAP / 2, MARK_H)


def dpad(c=DPAD_C, a=DPAD_ARM, t=DPAD_T):
    cx, cy = c
    pts = [(cx - t, cy - a), (cx + t, cy - a), (cx + t, cy - t), (cx + a, cy - t),
           (cx + a, cy + t), (cx + t, cy + t), (cx + t, cy + a), (cx - t, cy + a),
           (cx - t, cy + t), (cx - a, cy + t), (cx - a, cy - t), (cx - t, cy - t)]
    return rounded_polygon(pts, 4.0)


def dots(c=DOTS_C, off=DOT_OFF, r=DOT_R):
    cx, cy = c
    ops = []
    for dx, dy in ((0, -off), (off, 0), (0, off), (-off, 0)):
        ops += circle(cx + dx, cy + dy, r)
    return ops


def solid_mark():
    """The lockup mark: two filled halves with the d-pad and buttons cut out."""
    return [rounded_polygon(LEFT, CORNER) + dpad(),
            rounded_polygon(RIGHT, CORNER) + dots()]


def inset(pts, t):
    """Inset a convex, clockwise-on-screen polygon by t."""
    n = len(pts)
    lines = []
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        d = math.hypot(dx, dy)
        nx, ny = -dy / d, dx / d  # inward for clockwise-on-screen order
        lines.append(((x0 + nx * t, y0 + ny * t), (dx, dy)))
    out = []
    for i in range(n):
        (p, u), (q, v) = lines[i - 1], lines[i]
        den = u[0] * v[1] - u[1] * v[0]
        s = ((q[0] - p[0]) * v[1] - (q[1] - p[1]) * v[0]) / den
        out.append((p[0] + u[0] * s, p[1] + u[1] * s))
    return out


RING = 40.0
OPEN_Y = 104.0   # the ring is open along the cut from the top down to here


def _ring_half():
    """Left half of the outline mark as one simple polygon: a thick ring
    whose inside opens up through the upper part of the cut."""
    h = inset(LEFT, RING)               # hole corners: tip, TL, TR, BR, BL
    k = SLANT / MARK_H
    shift = RING * math.hypot(SLANT, MARK_H) / MARK_H   # cut width, horizontally
    x_out = lambda y: HALF_W - SLANT + k * y
    x_in = lambda y: x_out(y) - shift
    pts = [LEFT[0], LEFT[1], (x_in(0), 0), h[2], h[1], h[0], h[4], h[3],
           (x_in(OPEN_Y), OPEN_Y), (x_out(OPEN_Y), OPEN_Y), LEFT[3], LEFT[4]]
    return rounded_polygon(pts, 8.0)


def _rotate180(op):
    k = op[0]
    f = lambda x, y: (MARK_W - x, MARK_H - y)
    if k in ("M", "L"):
        return (k, *f(op[1], op[2]))
    if k == "Q":
        return (k, *f(op[1], op[2]), *f(op[3], op[4]))
    if k == "A":
        return (k, op[1], op[2], op[3], *f(op[4], op[5]))
    return op


OUT_DPAD = ((128.0, 100.0), 36.0, 12.0)
OUT_DOTS = ((MARK_W - 128.0, 100.0), 24.0, 12.0)


def outline_mark():
    """The app-icon mark: each half a thick hexagon ring, open where the cut
    runs (top of the left half, bottom of the right), with the d-pad and the
    four buttons standing inside."""
    ring = _ring_half()
    return [ring + dpad(*OUT_DPAD),
            [_rotate180(op) for op in ring] + dots(*OUT_DOTS)]


# ---- The wordmark: a light lowercase "ez" and a wide, heavy "CORE" ----
CAP = 100.0      # CORE cap height; baseline at y = CAP
STROKE = 26.0
LETTER_W = 132.0
LETTER_GAP = 18.0
EZ_X = 66.0      # x-height of "ez"
EZ_STROKE = 10.5
EZ_TO_CORE = 24.0


def _c_body(x0):
    w, r, s = LETTER_W, CAP / 2, STROKE
    ri = r - s
    return [("M", x0 + w, 0), ("L", x0 + r, 0), ("A", r, 0, 0, x0 + r, CAP),
            ("L", x0 + w, CAP), ("L", x0 + w, CAP - s), ("L", x0 + r, CAP - s),
            ("A", ri, 0, 1, x0 + r, s), ("L", x0 + w, s), ("Z",)]


def letter_c(x0):
    return [_c_body(x0)]


def letter_o(x0):
    w, r, s = LETTER_W, CAP / 2, STROKE
    ri = r - s
    outer = [("M", x0 + r, 0), ("L", x0 + w - r, 0), ("A", r, 0, 1, x0 + w - r, CAP),
             ("L", x0 + r, CAP), ("A", r, 0, 1, x0 + r, 0), ("Z",)]
    inner = [("M", x0 + r, s), ("L", x0 + w - r, s), ("A", ri, 0, 1, x0 + w - r, CAP - s),
             ("L", x0 + r, CAP - s), ("A", ri, 0, 1, x0 + r, s), ("Z",)]
    return [outer + inner]


def letter_r(x0):
    s = STROKE
    w = LETTER_W - 8
    br = 31.0          # bowl outer radius (bowl is 62 tall)
    stem = [("M", x0, 0), ("L", x0 + s, 0), ("L", x0 + s, CAP), ("L", x0, CAP), ("Z",)]
    bowl = [("M", x0, 0), ("L", x0 + w - br, 0), ("A", br, 0, 1, x0 + w - br, 2 * br),
            ("L", x0, 2 * br), ("Z",),
            ("M", x0 + s, 24), ("L", x0 + w - br, 24), ("A", 8, 0, 1, x0 + w - br, 40),
            ("L", x0 + s, 40), ("Z",)]
    leg = [("M", x0 + w - 64, 2 * br - 1), ("L", x0 + w - 36, 2 * br - 1),
           ("L", x0 + w, CAP), ("L", x0 + w - 28, CAP), ("Z",)]
    return [stem, bowl, leg]


def letter_e(x0):
    bar = [("M", x0 + STROKE - 2, 38), ("L", x0 + LETTER_W - 14, 38),
           ("L", x0 + LETTER_W - 14, 62), ("L", x0 + STROKE - 2, 62), ("Z",)]
    return [_c_body(x0), bar]


def letter_ez():
    """Lowercase "ez" on the CORE baseline, x-height EZ_X."""
    R = EZ_X / 2
    ri = R - EZ_STROKE
    cx, cy = R, CAP - R
    a = math.radians(38)  # the e's opening, below its bar on the right
    ox, oy = cx + R * math.cos(a), cy + R * math.sin(a)
    ix, iy = cx + ri * math.cos(a), cy + ri * math.sin(a)
    half = EZ_STROKE / 2
    # Ring from the bar (angle 0) clockwise... we go the long way round:
    # from the bar's right end, over the top, round the left, under, to the
    # opening; then back along the inside.
    e_ring = [("M", cx + R, cy - half + half),
              ("A", R, 1, 0, ox, oy),
              ("L", ix, iy),
              ("A", ri, 1, 1, cx + ri, cy),
              ("Z",)]
    e_bar = [("M", cx - ri - 1, cy - half), ("L", cx + R, cy - half),
             ("L", cx + R, cy + half), ("L", cx - ri - 1, cy + half), ("Z",)]
    zx = EZ_X + 8
    zw, t = 56.0, EZ_STROKE
    top = CAP - EZ_X
    z = rounded_polygon([(zx, top), (zx + zw, top), (zx + zw, top + t),
                         (zx + 14, CAP - t), (zx + zw, CAP - t), (zx + zw, CAP),
                         (zx, CAP), (zx, CAP - t), (zx + zw - 14, top + t),
                         (zx, top + t)], 1.5)
    return [e_ring, e_bar, z], zx + zw


def wordmark():
    """(shapes, width) for "ez CORE" with its baseline at y = CAP."""
    ez, ez_w = letter_ez()
    x = ez_w + EZ_TO_CORE
    shapes = list(ez)
    for f in (letter_c, letter_o, letter_r, letter_e):
        shapes += f(x)
        x += (LETTER_W - 8 if f is letter_r else LETTER_W) + LETTER_GAP
    return shapes, x - LETTER_GAP


# ---- SVG output ----

def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def svg_d(ops):
    out = []
    for op in ops:
        k = op[0]
        if k in ("M", "L"):
            out.append(f"{k}{fmt(op[1])} {fmt(op[2])}")
        elif k == "Q":
            out.append(f"Q{fmt(op[1])} {fmt(op[2])} {fmt(op[3])} {fmt(op[4])}")
        elif k == "A":
            out.append(f"A{fmt(op[1])} {fmt(op[1])} 0 {op[2]} {op[3]} {fmt(op[4])} {fmt(op[5])}")
        else:
            out.append("Z")
    return "".join(out)


def svg_paths(shapes, fill, extra=""):
    return "".join(
        f'<path fill-rule="evenodd" fill="{fill}"{extra} d="{svg_d(s)}"/>' for s in shapes)


def cut_light(uid, scale=1.0):
    """The blue light running along the cut, fading at both ends."""
    (x0, y0), (x1, y1) = CUT_TOP, CUT_BOTTOM
    ext = 0.10
    ax, ay = x0 - (x1 - x0) * ext, y0 - (y1 - y0) * ext
    bx, by = x1 + (x1 - x0) * ext, y1 + (y1 - y0) * ext
    return f"""
  <defs>
    <linearGradient id="{uid}-g" gradientUnits="userSpaceOnUse" x1="{fmt(ax)}" y1="{fmt(ay)}" x2="{fmt(bx)}" y2="{fmt(by)}">
      <stop offset="0" stop-color="{BLUE}" stop-opacity="0"/>
      <stop offset="0.35" stop-color="{BLUE}" stop-opacity="0.9"/>
      <stop offset="0.5" stop-color="#7DB9FF" stop-opacity="1"/>
      <stop offset="0.65" stop-color="{BLUE}" stop-opacity="0.9"/>
      <stop offset="1" stop-color="{BLUE}" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="{uid}-c" gradientUnits="userSpaceOnUse" x1="{fmt(ax)}" y1="{fmt(ay)}" x2="{fmt(bx)}" y2="{fmt(by)}">
      <stop offset="0.2" stop-color="#FFFFFF" stop-opacity="0"/>
      <stop offset="0.5" stop-color="#FFFFFF" stop-opacity="1"/>
      <stop offset="0.8" stop-color="#FFFFFF" stop-opacity="0"/>
    </linearGradient>
    <filter id="{uid}-blur" x="-50%" y="-20%" width="200%" height="140%"><feGaussianBlur stdDeviation="{fmt(7 * scale)}"/></filter>
  </defs>
  <g stroke-linecap="round">
    <line x1="{fmt(ax)}" y1="{fmt(ay)}" x2="{fmt(bx)}" y2="{fmt(by)}" stroke="url(#{uid}-g)" stroke-width="14" filter="url(#{uid}-blur)"/>
    <line x1="{fmt(ax)}" y1="{fmt(ay)}" x2="{fmt(bx)}" y2="{fmt(by)}" stroke="url(#{uid}-g)" stroke-width="4"/>
    <line x1="{fmt(ax)}" y1="{fmt(ay)}" x2="{fmt(bx)}" y2="{fmt(by)}" stroke="url(#{uid}-c)" stroke-width="1.6"/>
  </g>"""


def doc(w, h, body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fmt(w)} {fmt(h)}" '
            f'width="{fmt(w)}" height="{fmt(h)}" role="img" aria-label="{title}">\n'
            f"  <title>{title}</title>{body}\n</svg>\n")


def mark_svg(fill, light=True, outline=False, uid="m"):
    shapes = outline_mark() if outline else solid_mark()
    body = "\n  " + svg_paths(shapes, fill)
    if light:
        body += cut_light(uid)
    return body


TM = '<text x="{x}" y="{y}" font-family="Manrope, sans-serif" font-size="{s}" font-weight="600" fill="{f}">TM</text>'


def lockup_svg(ink, title, tm=True):
    """Mark + wordmark side by side, as on the sheet."""
    words, ww = wordmark()
    k = 1.26                      # CORE cap = 63% of the mark's height
    gap = 59.0
    pad = 24.0
    w = pad + MARK_W + gap + ww * k + (36 if tm else 0) + pad
    h = MARK_H + 2 * pad
    wy = pad + (MARK_H - CAP * k) / 2
    body = f'\n  <g transform="translate({fmt(pad)} {fmt(pad)})">{mark_svg(ink, uid="lk")}\n  </g>'
    body += (f'\n  <g transform="translate({fmt(pad + MARK_W + gap)} {fmt(wy)}) scale({k})">'
             f"{svg_paths(words, ink)}</g>")
    if tm:
        body += "\n  " + TM.format(x=fmt(pad + MARK_W + gap + ww * k + 6),
                                   y=fmt(wy + 18), s=18, f=ink)
    return doc(w, h, body, title)


def wordmark_svg(ink):
    words, ww = wordmark()
    return doc(ww, CAP, "\n  " + svg_paths(words, ink), "ezCORE")


def icon_svg(variant, size=1024, full_bleed=False):
    """Mark-only icons, the sheet's three variations."""
    m = size * 0.08 if not full_bleed else 0
    s = size - 2 * m
    r = 0 if full_bleed else s * 0.225
    scale = (s * 0.74) / MARK_W
    mx = m + (s - MARK_W * scale) / 2
    my = m + (s - MARK_H * scale) / 2
    if variant == "dark":
        bg = (f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
              f'<stop offset="0" stop-color="#151A22"/><stop offset="1" stop-color="{INK}"/></linearGradient>')
        fill, ink, outline, edge = "url(#bg)", WHITE, True, "#FFFFFF14"
    elif variant == "light":
        bg = (f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
              f'<stop offset="0" stop-color="{WHITE}"/><stop offset="1" stop-color="#EEF2F8"/></linearGradient>')
        fill, ink, outline, edge = "url(#bg)", INK, False, "#0A0A0A14"
    else:  # blue
        bg = (f'<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
              f'<stop offset="0" stop-color="#1F8BFF"/><stop offset="1" stop-color="#0062E0"/></linearGradient>')
        fill, ink, outline, edge = "url(#bg)", WHITE, True, "#FFFFFF26"
    body = f"\n  <defs>{bg}</defs>"
    body += (f'\n  <rect x="{fmt(m)}" y="{fmt(m)}" width="{fmt(s)}" height="{fmt(s)}" '
             f'rx="{fmt(r)}" fill="{fill}"/>')
    if not full_bleed:
        body += (f'\n  <rect x="{fmt(m + 1)}" y="{fmt(m + 1)}" width="{fmt(s - 2)}" height="{fmt(s - 2)}" '
                 f'rx="{fmt(r - 1)}" fill="none" stroke="{edge}" stroke-width="2"/>')
    body += (f'\n  <g transform="translate({fmt(mx)} {fmt(my)}) scale({fmt(scale)})">'
             f'{mark_svg(ink, light=(variant == "dark"), outline=outline, uid="ic")}\n  </g>')
    return doc(size, size, body, "ezCORE")


def app_icon_svg(size=1024):
    """The sheet's hero icon: dark glass tile, blue rim light, silver mark
    and the wordmark beneath."""
    m = size * 0.11
    s = size - 2 * m
    r = s * 0.225
    words, ww = wordmark()
    mk = (s * 0.74) / MARK_W
    mx = m + (s - MARK_W * mk) / 2
    my = m + s * 0.20
    wk = (s * 0.66) / ww
    wx = m + (s - ww * wk) / 2
    wy = m + s * 0.66
    body = f"""
  <defs>
    <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#0E1626"/><stop offset="1" stop-color="#05070C"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.5" cy="0.18" r="0.75">
      <stop offset="0" stop-color="#1B2C48" stop-opacity="0.9"/><stop offset="1" stop-color="#1B2C48" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="silver" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#F7F9FC"/><stop offset="0.55" stop-color="#D3DBE8"/><stop offset="1" stop-color="#AEB9CC"/>
    </linearGradient>
    <filter id="rimglow" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="{fmt(size * 0.018)}"/></filter>
  </defs>
  <rect x="{fmt(m)}" y="{fmt(m)}" width="{fmt(s)}" height="{fmt(s)}" rx="{fmt(r)}" fill="none" stroke="{BLUE}" stroke-width="{fmt(size * 0.012)}" filter="url(#rimglow)" opacity="0.95"/>
  <rect x="{fmt(m)}" y="{fmt(m)}" width="{fmt(s)}" height="{fmt(s)}" rx="{fmt(r)}" fill="url(#tile)"/>
  <rect x="{fmt(m)}" y="{fmt(m)}" width="{fmt(s)}" height="{fmt(s)}" rx="{fmt(r)}" fill="url(#sheen)"/>
  <rect x="{fmt(m)}" y="{fmt(m)}" width="{fmt(s)}" height="{fmt(s)}" rx="{fmt(r)}" fill="none" stroke="#3D95FF" stroke-width="{fmt(size * 0.004)}"/>
  <g transform="translate({fmt(mx)} {fmt(my)}) scale({fmt(mk)})">{mark_svg("url(#silver)", outline=True, uid="hero")}
  </g>
  <g transform="translate({fmt(wx)} {fmt(wy)}) scale({fmt(wk)})">{svg_paths(words, "url(#silver)")}</g>"""
    return doc(size, size, body, "ezCORE")


def social_svg():
    """1280x640 repository card: the sheet's light panel."""
    w, h = 1280, 640
    words, ww = wordmark()
    k = 1.26
    lock_w = MARK_W + 59 + ww * k
    s = 900 / lock_w
    lx = (w - lock_w * s) / 2
    ly = 150
    wy = ly + (MARK_H - CAP * k) / 2 * s
    body = f"""
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#E9EEF6"/>
    </linearGradient>
  </defs>
  <rect width="{w}" height="{h}" fill="url(#bg)"/>
  <g transform="translate({fmt(lx)} {fmt(ly)}) scale({fmt(s)})">{mark_svg(INK, uid="soc")}
  </g>
  <g transform="translate({fmt(lx + (MARK_W + 59) * s)} {fmt(wy)}) scale({fmt(k * s)})">{svg_paths(words, INK)}</g>
  <text x="{w / 2}" y="420" text-anchor="middle" font-family="Manrope, sans-serif" font-size="27" font-weight="500" letter-spacing="13" fill="#2A2F38">EMULATION SHOULDN’T BE HARD.</text>
  <line x1="200" y1="470" x2="1080" y2="470" stroke="#C9D2DF" stroke-width="1.5"/>
  <g font-family="Manrope, sans-serif" font-size="19" font-weight="500" letter-spacing="9" fill="#3A404B" text-anchor="middle">
    <text x="360" y="528">SIMPLE</text><text x="640" y="528">POWERFUL</text><text x="920" y="528">EVERYWHERE</text>
  </g>
  <g stroke="#9AA6B8" stroke-width="1.5"><line x1="500" y1="508" x2="500" y2="534"/><line x1="780" y1="508" x2="780" y2="534"/></g>"""
    return doc(w, h, body, "ezCORE — Emulation shouldn't be hard.")


def palette_svg():
    sw = [(INK, "#0A0A0A"), (BLUE, "#007BFF"), (MIST, "#DDE6F4"), (WHITE, "#FFFFFF")]
    body = '\n  <rect width="560" height="200" fill="#F4F6FA"/>'
    for i, (c, label) in enumerate(sw):
        x = 70 + i * 140
        body += (f'\n  <circle cx="{x}" cy="80" r="44" fill="{c}" stroke="#D5DCE6" stroke-width="2"/>'
                 f'<text x="{x}" y="160" text-anchor="middle" font-family="Manrope, sans-serif" '
                 f'font-size="17" letter-spacing="1.5" fill="#3A404B">{label}</text>')
    return doc(560, 200, body, "ezCORE palette")


# ---- Dart output: the same paths for the in-app painter ----

def dart_ops(name, shapes):
    lines = [f"final List<Path> {name} = ["]
    for s in shapes:
        lines.append("  Path()")
        lines.append("    ..fillType = PathFillType.evenOdd")
        for op in s:
            k = op[0]
            if k == "M":
                lines.append(f"    ..moveTo({op[1]:.2f}, {op[2]:.2f})")
            elif k == "L":
                lines.append(f"    ..lineTo({op[1]:.2f}, {op[2]:.2f})")
            elif k == "Q":
                lines.append(f"    ..quadraticBezierTo({op[1]:.2f}, {op[2]:.2f}, {op[3]:.2f}, {op[4]:.2f})")
            elif k == "A":
                lines.append(
                    f"    ..arcToPoint(const Offset({op[4]:.2f}, {op[5]:.2f}), "
                    f"radius: const Radius.circular({op[1]:.2f}), "
                    f"largeArc: {'true' if op[2] else 'false'}, "
                    f"clockwise: {'true' if op[3] else 'false'})")
            else:
                lines.append("    ..close()")
        lines[-1] += ","
    lines.append("];")
    return "\n".join(lines)


def write_dart():
    words, ww = wordmark()
    src = f"""// GENERATED by scripts/build_brand.py — do not edit by hand.
//
// The ezCORE mark and wordmark as Flutter paths: the same geometry as the
// SVG files in assets/branding/, so the app's logo matches them exactly.
// ignore_for_file: prefer_const_declarations

import 'dart:ui';

/// Mark box (logical units).
const double markWidth = {MARK_W};
const double markHeight = {MARK_H};

/// The cut between the two halves, where the blue light runs.
const Offset cutTop = Offset({CUT_TOP[0]}, {CUT_TOP[1]});
const Offset cutBottom = Offset({CUT_BOTTOM[0]}, {CUT_BOTTOM[1]});

/// Wordmark box: "ez CORE", baseline at [wordmarkHeight].
const double wordmarkWidth = {ww:.2f};
const double wordmarkHeight = {CAP};

{dart_ops("solidMarkPaths", solid_mark())}

{dart_ops("wordmarkPaths", words)}
"""
    path = os.path.join(ROOT, "lib", "brand", "brand_paths.g.dart")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(src)
    return path


# ---- Rendering ----

def write(name, text):
    p = os.path.join(OUT, name)
    with open(p, "w") as f:
        f.write(text)
    return p


def fontconfig_env():
    """Let rsvg find the bundled Manrope for the few text labels."""
    d = tempfile.mkdtemp(prefix="ezbrand-fc-")
    conf = os.path.join(d, "fonts.conf")
    with open(conf, "w") as f:
        f.write(f"""<?xml version="1.0"?><!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig><include ignore_missing="yes">/etc/fonts/fonts.conf</include>
<dir>{os.path.join(ROOT, "assets", "fonts")}</dir><cachedir>{d}</cachedir></fontconfig>""")
    env = dict(os.environ, FONTCONFIG_FILE=conf)
    return env, d


def render(svg, png, w, h=None, env=None):
    os.makedirs(os.path.dirname(png), exist_ok=True)
    cmd = ["rsvg-convert", "-w", str(w)] + (["-h", str(h)] if h else []) + ["-o", png, svg]
    subprocess.run(cmd, check=True, env=env)


def main():
    svg_only = "--svg-only" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    words, ww = wordmark()
    svgs = {
        "mark.svg": doc(MARK_W, MARK_H, mark_svg(INK, uid="m"), "ezCORE mark"),
        "mark-white.svg": doc(MARK_W, MARK_H, mark_svg(WHITE, uid="m"), "ezCORE mark"),
        "mark-outline.svg": doc(MARK_W, MARK_H, mark_svg(WHITE, outline=True, uid="m"), "ezCORE mark"),
        "wordmark-dark.svg": wordmark_svg(INK),
        "wordmark-light.svg": wordmark_svg(WHITE),
        "lockup-dark.svg": lockup_svg(INK, "ezCORE"),
        "lockup-light.svg": lockup_svg(WHITE, "ezCORE"),
        "icon-dark.svg": icon_svg("dark"),
        "icon-light.svg": icon_svg("light"),
        "icon-blue.svg": icon_svg("blue"),
        "icon-ios.svg": icon_svg("dark", full_bleed=True),
        "app-icon.svg": app_icon_svg(),
        "social-preview.svg": social_svg(),
        "palette.svg": palette_svg(),
    }
    for name, text in svgs.items():
        write(name, text)
    dart = write_dart()
    print(f"wrote {len(svgs)} SVGs to {OUT} and {os.path.relpath(dart, ROOT)}")
    if svg_only:
        return
    if not shutil.which("rsvg-convert"):
        sys.exit("rsvg-convert not found (librsvg); re-run with --svg-only")
    env, tmp = fontconfig_env()
    try:
        b = lambda n: os.path.join(OUT, n)
        render(b("app-icon.svg"), b("app-icon-1024.png"), 1024, env=env)
        for v in ("dark", "light", "blue"):
            render(b(f"icon-{v}.svg"), b(f"icon-{v}.png"), 512, env=env)
        render(b("lockup-dark.svg"), b("lockup-dark.png"), 1400, env=env)
        render(b("lockup-light.svg"), b("lockup-light.png"), 1400, env=env)
        render(b("mark-white.svg"), b("mark-white.png"), 512, env=env)
        render(b("social-preview.svg"), b("social-preview.png"), 1280, 640, env=env)
        render(b("palette.svg"), b("palette.png"), 1120, env=env)
        # Platform launcher icons.
        icon = b("icon-dark.svg")
        ios = b("icon-ios.svg")
        android = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
        for d, px in android.items():
            render(icon, os.path.join(ROOT, f"android/app/src/main/res/mipmap-{d}/ic_launcher.png"), px)
        mac = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
        for px in (16, 32, 64, 128, 256, 512, 1024):
            render(icon, os.path.join(mac, f"app_icon_{px}.png"), px)
        iosdir = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
        for fn in sorted(os.listdir(iosdir)):
            if not fn.endswith(".png"):
                continue
            base = fn[len("Icon-App-"):-len(".png")]  # e.g. 20x20@2x
            pt, mult = base.split("@")
            px = round(float(pt.split("x")[0]) * int(mult.rstrip("x")))
            tmp_png = os.path.join(tmp, fn)
            render(ios, tmp_png, px)
            # The App Store rejects icons with an alpha channel.
            subprocess.run(["magick", tmp_png, "-background", INK, "-alpha", "remove",
                            "-alpha", "off", os.path.join(iosdir, fn)], check=True)
        render(icon, os.path.join(ROOT, "linux/runner/resources/app_icon.png"), 256)
        ico_parts = []
        for px in (16, 24, 32, 48, 64, 128, 256):
            p = os.path.join(tmp, f"ico{px}.png")
            render(icon, p, px)
            ico_parts.append(p)
        if shutil.which("magick"):
            subprocess.run(["magick", *ico_parts, os.path.join(ROOT, "windows/runner/resources/app_icon.ico")], check=True)
        print("rendered PNGs and platform icons")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
