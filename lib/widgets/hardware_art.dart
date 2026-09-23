/// Hardware silhouettes for the Systems browser — Dart port of the finalized
/// Orbit console `hardware-art.js` (black / electric blue / silver identity).
/// Same shapes, palette, gradients and 320x240 viewBox; rendered with
/// flutter_svg via [hardwareSvg]. The LED highlight opacity quirk in the
/// original helper is emitted correctly here (`opacity="0.6"`).
library;

// ignore_for_file: prefer_interpolation_to_compose_strings

const _s = '#DDE6F4';
const _sl = '#EAF0FB';
const _sd = '#B0BFD8';
const _sh = '#7A8AA0';
const _k = '#0A0A0A';
const _kl = '#1E1E2E';
const _kd = '#050508';
const _b = '#007BFF';
const _bl = '#4DA3FF';
const _bd = '#005BBF';
const _gr = '#6B7B8F';

String _uid(String core, String sfx) =>
    'ha_${core.replaceAll(RegExp(r'[^a-z0-9]', caseSensitive: false), '_')}_$sfx';

String _open(String label) =>
    '<svg class="hardware-art" viewBox="0 0 320 240" role="img" aria-label="$label" xmlns="http://www.w3.org/2000/svg">';

String _close() => '</svg>';

String _lg(String id, num y1, num y2, String c0, String c1) =>
    '<linearGradient id="$id" x1="0%" y1="$y1%" x2="0%" y2="$y2%"><stop offset="0%" stop-color="$c0"/><stop offset="100%" stop-color="$c1"/></linearGradient>';

String _r(num x, num y, num w, num h, String fill,
    [num? rx, String? stroke, num? sw]) {
  final a = rx != null ? ' rx="$rx"' : '';
  final b =
      stroke != null ? ' stroke="$stroke" stroke-width="${sw ?? 1}"' : '';
  return '<rect x="$x" y="$y" width="$w" height="$h"$a fill="$fill"$b/>';
}

String _c(num cx, num cy, num rd, String fill, [String? stroke]) {
  final a = stroke != null ? ' stroke="$stroke" stroke-width="1"' : '';
  return '<circle cx="$cx" cy="$cy" r="$rd" fill="$fill"$a/>';
}

String _e(num cx, num cy, num rx, num ry, String fill, [String? stroke]) {
  final a = stroke != null ? ' stroke="$stroke" stroke-width="1"' : '';
  return '<ellipse cx="$cx" cy="$cy" rx="$rx" ry="$ry" fill="$fill"$a/>';
}

String _p(String pts, String fill, [String? stroke]) {
  final a = stroke != null ? ' stroke="$stroke" stroke-width="1"' : '';
  return '<polygon points="$pts" fill="$fill"$a/>';
}

String _line(num x1, num y1, num x2, num y2, String stroke,
    [num sw = 1, String extra = '']) {
  final e = extra.isEmpty ? '' : ' $extra';
  return '<line x1="$x1" y1="$y1" x2="$x2" y2="$y2" stroke="$stroke" stroke-width="$sw"$e/>';
}

String _dpad(num cx, num cy, num w, num h) =>
    '<g>' +
    _r(cx - w * 1.4, cy - h * 0.4, w * 2.8, h * 0.8, _kl, 2) +
    _r(cx - h * 0.4, cy - w * 1.4, h * 0.8, w * 2.8, _kl, 2) +
    '</g>';

String _pill(num x, num y, num w, num h, String fill) =>
    _r(x, y, w, h, fill, h / 2);

String _led(num cx, num cy, num r, String color) =>
    '<g>' +
    _c(cx, cy, r, color) +
    '<circle cx="${cx - r * 0.3}" cy="${cy - r * 0.3}" r="${r * 0.4}" fill="#fff" opacity="0.6"/>' +
    '</g>';

String _text(num x, num y, String body, String fill, num size,
    [String family = 'monospace', String extra = '']) {
  final e = extra.isEmpty ? '' : ' $extra';
  return '<text x="$x" y="$y" fill="$fill" font-size="$size" font-family="$family"$e>$body</text>';
}

// ── Game Boy (sameboy / gambatte) ──────────
String _gb(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, _sl, _sd);
  var s = _open('Game Boy original portrait handheld');
  s += '<defs>$d</defs>';
  s += _r(100, 30, 120, 250, 'url(#${_uid(id, 'bg')})', 18, _sh, 2);
  s += _r(100, 30, 120, 12, _sl, 10);
  s += _r(114, 52, 92, 88, _k, 8);
  s += _r(118, 56, 84, 80, _bd, 5);
  s += _r(122, 60, 76, 72, _b, 4);
  s += _line(126, 64, 155, 64, _bl, 1.5, 'opacity="0.55"');
  s += _led(128, 158, 4, '#FF4444');
  s += _dpad(138, 190, 22, 8);
  s += _c(184, 195, 13, _k) + _c(184, 195, 10, _kl) + _c(184, 195, 4, '#222236');
  s += _c(158, 212, 13, _k) + _c(158, 212, 10, _kl) + _c(158, 212, 4, '#222236');
  s += _pill(128, 242, 34, 10, _kl);
  s += _pill(128, 242, 30, 7, '#222236');
  s += _pill(185, 242, 34, 10, _kl);
  s += _pill(185, 242, 30, 7, '#222236');
  for (var i = 0; i < 6; i++) {
    s += _line(158 + i * 7, 260, 158 + i * 7, 274, _kl, 2.5,
        'stroke-linecap="round"');
  }
  s += _close();
  return s;
}

// ── Game Boy Advance (mgba) ──
String _gba(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, _sl, _sd);
  var s = _open('Game Boy Advance landscape handheld with side grips');
  s += '<defs>$d</defs>';
  s += _r(30, 70, 260, 110, 'url(#${_uid(id, 'bg')})', 12, _sh, 2);
  s += _r(15, 80, 50, 90, _s, 20, _sh, 1);
  s += _r(15, 80, 50, 90, 'url(#${_uid(id, 'bg')})', 20);
  s += _r(255, 80, 50, 90, _s, 20, _sh, 1);
  s += _r(255, 80, 50, 90, 'url(#${_uid(id, 'bg')})', 20);
  s += _r(110, 80, 100, 70, _k, 5);
  s += _r(114, 84, 92, 62, _bd, 3);
  s += _r(118, 88, 84, 54, _b, 2);
  s += _dpad(55, 110, 14, 6);
  s += _c(268, 100, 9, _k) + _c(268, 100, 7, _kl);
  s += _c(282, 115, 9, _k) + _c(282, 115, 7, _kl);
  s += _r(30, 65, 40, 12, _kl, 4, _sh, 1);
  s += _r(250, 65, 40, 12, _kl, 4, _sh, 1);
  s += _pill(145, 158, 24, 8, _kl);
  s += _pill(178, 158, 24, 8, _kl);
  s += _led(200, 75, 2.5, '#44FF44');
  s += _close();
  return s;
}

// ── NES (mesen) ──
String _nes(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, _sl, '#9AACB8');
  var s = _open('Nintendo Entertainment System front-loading deck');
  s += '<defs>$d</defs>';
  s += _r(30, 80, 260, 70, 'url(#${_uid(id, 'bg')})', 4, _sh, 2);
  for (var i = 0; i < 8; i++) {
    s += _line(40 + i * 30, 82, 40 + i * 30, 110, '#B0BCC8', 1,
        'opacity="0.5"');
  }
  s += _r(80, 150, 160, 35, _k, 3, _sh, 1);
  s += _r(85, 153, 150, 12, _kl, 2);
  s += _r(140, 170, 40, 10, _gr, 3, _sh, 1);
  s += _r(100, 125, 20, 8, _kd, 1);
  s += _r(200, 125, 20, 8, _kd, 1);
  s += _led(95, 142, 3, _b);
  s += _r(80, 148, 160, 4, _kd);
  s += _r(140, 152, 30, 8, _k, 1);
  s += _close();
  return s;
}

// ── SNES (snes9x) ──
String _snes(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#D8DDE8', '#98A4B8');
  var s = _open('Super Nintendo rounded deck');
  s += '<defs>$d</defs>';
  s += _r(35, 75, 250, 90, 'url(#${_uid(id, 'bg')})', 16, _sh, 2);
  s += _r(120, 72, 80, 12, _kl, 3, _sh, 1);
  s += _r(130, 68, 60, 10, _k, 2, _sh, 1);
  s += _r(80, 105, 30, 14, '#8B6F9B', 3, _sh, 1);
  s += _r(120, 105, 30, 14, '#8B6F9B', 3, _sh, 1);
  s += _r(80, 105, 30, 14, _bd, 3);
  s += _r(120, 105, 30, 14, _bd, 3);
  s += _c(250, 112, 5, _kl) + _c(250, 112, 3, '#2A2A3A');
  s += _led(75, 112, 3, _b);
  s += _r(145, 135, 14, 7, _kd, 1);
  s += _r(165, 135, 14, 7, _kd, 1);
  s += _r(200, 76, 20, 6, _kl, 2);
  s += _r(225, 76, 20, 6, _kl, 2);
  s += _close();
  return s;
}

// ── N64 (mupen64plus) ──
String _n64(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#DCDDE4', '#A8ADB8');
  var s = _open('Nintendo 64 three-prong controller and console');
  s += '<defs>$d</defs>';
  s += _r(40, 200, 100, 28, 'url(#${_uid(id, 'bg')})', 3, _sh, 1);
  s += _r(44, 203, 20, 6, _kl, 1);
  s += _led(130, 210, 2.5, _b);
  s += _r(175, 80, 60, 50, _s, 8, _sh, 1);
  s += _p('155,130 200,130 185,195 145,195', _s, _sh);
  s += _p('235,130 210,130 220,195 250,195', _s, _sh);
  s += _p('185,180 220,180 230,140 175,140', _s, _sh);
  s += _c(200, 120, 12, _k) + _c(200, 120, 9, _kl) + _c(200, 120, 3, _b);
  s += _dpad(160, 160, 10, 4);
  s += _c(220, 95, 11, _k) + _c(220, 95, 8, _bd);
  s += _c(240, 105, 9, _k) + _c(240, 105, 7, '#4A2A2A');
  s += _c(215, 70, 5, _b, _sh) + _c(230, 65, 5, _b, _sh) + _c(245, 70, 5, _b, _sh);
  s += _r(190, 195, 30, 8, _kl, 3, _sh, 1);
  s += _led(200, 205, 3, _b);
  s += _close();
  return s;
}

// ── DS (melonds) ──
String _ds(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, _sl, _sd);
  var s = _open('Nintendo DS open clamshell with two screens');
  s += '<defs>$d</defs>';
  s += _r(60, 140, 200, 85, 'url(#${_uid(id, 'bg')})', 8, _sh, 2);
  s += _r(60, 20, 200, 110, _s, 8, _sh, 2);
  s += _r(130, 128, 60, 14, _kl, 3, _sh, 1);
  s += _r(78, 32, 164, 80, _k, 4);
  s += _r(82, 36, 156, 72, _bd, 3);
  s += _r(86, 40, 148, 64, _b, 2);
  s += _r(78, 152, 164, 60, _k, 4);
  s += _r(82, 156, 156, 52, '#1A2A4A', 3);
  s += _r(86, 160, 148, 44, _b, 2);
  s += '<text x="160" y="188" text-anchor="middle" fill="$_bl" font-size="7" font-family="monospace" opacity="0.7">TOUCH</text>';
  s += _dpad(108, 195, 8, 3);
  s += _c(215, 188, 6, _k) + _c(215, 188, 4, '#3A2020');
  s += _c(228, 200, 6, _k) + _c(228, 200, 4, '#20203A');
  s += _c(202, 200, 6, _k) + _c(202, 200, 4, '#203A20');
  s += _c(215, 212, 6, _k) + _c(215, 212, 4, '#3A3A20');
  s += _pill(148, 222, 18, 6, _kl);
  s += _pill(172, 222, 18, 6, _kl);
  s += _c(160, 235, 3, _kd);
  s += _led(90, 25, 2, '#44FF44');
  s += _close();
  return s;
}

// ── Dolphin — GameCube + Wii ──
String _dolphin(String id) {
  final dg = _lg(_uid(id, 'gc'), 0, 100, '#B8B8CC', '#808098');
  final dw = _lg(_uid(id, 'wi'), 0, 100, '#E8ECF0', '#C0C8D0');
  var s = _open('Nintendo GameCube cube and slim Wii console');
  s += '<defs>$dg$dw</defs>';
  s += _r(40, 100, 100, 100, 'url(#${_uid(id, 'gc')})', 4, _sh, 2);
  s += _c(90, 100, 40, '#9090A8', _sh);
  s += _c(90, 100, 35, '#A8A8BC');
  s += _c(90, 100, 10, '#7878A0');
  s += '<path d="M 50,100 Q 90,75 130,100" stroke="$_sh" stroke-width="2" fill="none"/>';
  s += _r(60, 160, 12, 6, _k, 1);
  s += _r(78, 160, 12, 6, _k, 1);
  s += _r(96, 160, 12, 6, _k, 1);
  s += _r(114, 160, 12, 6, _k, 1);
  s += _c(90, 140, 8, _k) + _c(90, 140, 5, '#2A2A3A');
  s += _c(108, 140, 4, _k);
  s += _r(190, 120, 100, 60, 'url(#${_uid(id, 'wi')})', 6, _sh, 2);
  s += _r(195, 145, 90, 8, _kl, 2);
  s += _r(200, 160, 14, 6, _kd, 1);
  s += _r(220, 160, 14, 6, _kd, 1);
  s += _led(275, 130, 3, _b);
  s += _c(90, 140, 5, _b);
  s += _r(185, 180, 110, 8, '#B0B8C4', 2, _sh, 1);
  s += _close();
  return s;
}

// ── PlayStation (swanstation) ──
String _ps1(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#D8DCE4', '#A0A8B4');
  var s = _open('Original PlayStation with circular disc lid');
  s += '<defs>$d</defs>';
  s += _r(50, 90, 220, 70, 'url(#${_uid(id, 'bg')})', 6, _sh, 2);
  s += _e(160, 88, 80, 18, '#C0C8D4', _sh);
  s += _e(160, 88, 70, 14, '#B0B8C8');
  s += _e(160, 88, 30, 5, '#98A0B0');
  s += _line(80, 100, 240, 100, _sh, 1.5);
  s += _r(100, 110, 22, 10, _bd, 3, _sh, 1);
  s += _r(130, 110, 22, 10, _kl, 3, _sh, 1);
  s += _r(165, 110, 16, 8, _k, 2);
  s += _r(187, 110, 16, 8, _k, 2);
  s += _r(220, 95, 30, 8, '#5A5A6A', 1, _sh, 1);
  s += _c(210, 115, 3, _k);
  s += _led(90, 115, 2.5, _b);
  s += _close();
  return s;
}

// ── PSP (ppsspp) ──
String _psp(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#2A2A30', '#0A0A0E');
  var s = _open('PlayStation Portable wide black handheld');
  s += '<defs>$d</defs>';
  s += _r(20, 60, 280, 120, 'url(#${_uid(id, 'bg')})', 10, '#333340', 2);
  s += _r(95, 72, 130, 86, _k, 5);
  s += _r(100, 77, 120, 76, _bd, 3);
  s += _r(104, 81, 112, 68, _b, 2);
  s += _dpad(65, 120, 12, 5);
  s += _c(255, 105, 7, '#888898') + _c(255, 105, 5, '#AAAAB8');
  s += _c(268, 118, 7, '#888898') + _c(268, 118, 5, '#AAAAB8');
  s += _c(242, 118, 7, '#888898') + _c(242, 118, 5, '#AAAAB8');
  s += _c(255, 131, 7, '#888898') + _c(255, 131, 5, '#AAAAB8');
  s += _c(70, 150, 8, '#333340') + _c(70, 150, 5, '#444455');
  s += _r(30, 55, 35, 10, '#1A1A22', 3, '#333340', 1);
  s += _r(255, 55, 35, 10, '#1A1A22', 3, '#333340', 1);
  s += _pill(140, 158, 18, 6, '#333340');
  s += _pill(165, 158, 18, 6, '#333340');
  s += _c(190, 161, 5, '#333340');
  s += _close();
  return s;
}

// ── Mega Drive (genesis_plus_gx) ──
String _md(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#D4D4DC', '#9098A4');
  var s = _open('Sega Mega Drive oval deck with cartridge slot');
  s += '<defs>$d</defs>';
  s += _r(40, 80, 240, 80, 'url(#${_uid(id, 'bg')})', 12, _sh, 2);
  s += _r(135, 72, 50, 14, _k, 2, _sh, 1);
  s += _r(138, 74, 44, 3, _kl);
  s += _e(160, 80, 120, 14, _s, _sh);
  s += _r(70, 100, 22, 10, _k, 3, _sh, 1);
  s += _r(72, 102, 18, 6, '#2A2A3A', 2);
  s += _c(105, 105, 6, _k) + _c(105, 105, 4, '#2A2A3A');
  s += _r(210, 100, 30, 6, _kl, 2);
  s += _r(220, 101, 8, 4, '#4A4A5A', 1);
  s += _r(110, 130, 14, 6, _k, 1);
  s += _r(130, 130, 14, 6, _k, 1);
  s += _r(150, 130, 14, 6, _k, 1);
  s += _led(70, 125, 3, _b);
  s += _close();
  return s;
}

// ── Saturn (beetle_saturn) ──
String _saturn(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#E0E2E8', '#B0B4C0');
  var s = _open('Sega Saturn circular lid deck');
  s += '<defs>$d</defs>';
  s += _r(50, 95, 220, 70, 'url(#${_uid(id, 'bg')})', 8, _sh, 2);
  s += _e(160, 92, 75, 16, '#C8CCD4', _sh);
  s += _e(160, 92, 65, 12, '#B8BCC8');
  s += _e(160, 92, 25, 5, '#A0A4B0');
  s += _line(85, 105, 235, 105, _sh, 1.5);
  s += _c(100, 120, 9, _k, _sh) +
      _c(100, 120, 6, '#3A3A4A') +
      _c(100, 120, 2, '#5A5A6A');
  s += _r(130, 117, 24, 10, _bd, 3, _sh, 1);
  s += _r(170, 130, 14, 6, _k, 1);
  s += _r(190, 130, 14, 6, _k, 1);
  s += _led(80, 120, 3, _b);
  s += _close();
  return s;
}

// ── Dreamcast (flycast) ──
String _dreamcast(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#D8DAE0', '#A8ACB4');
  var s = _open('Sega Dreamcast square disc lid with four front controller ports');
  s += '<defs>$d</defs>';
  s += _r(60, 90, 200, 75, 'url(#${_uid(id, 'bg')})', 6, _sh, 2);
  s += _r(110, 78, 100, 20, '#B8BCC4', 4, _sh, 1);
  s += _r(115, 80, 90, 16, '#A8ACB4', 3);
  s += _r(125, 83, 70, 10, '#989CA8', 2);
  s += _line(70, 105, 250, 105, _sh, 1.5);
  s += _r(90, 110, 28, 10, _k, 3, _sh, 1);
  s += _r(128, 110, 28, 10, _k, 3, _sh, 1);
  for (final px in [168, 186, 204, 222]) {
    s += _r(px, 125, 12, 6, _k, 1);
    s += _r(px, 118, 12, 4, _k, 1);
  }
  s += _led(80, 115, 3, _b);
  s += _close();
  return s;
}

// ── PC Engine (beetle_pce) ──
String _pce(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#E0E4EA', '#B0B8C4');
  var s = _open('PC Engine small square deck');
  s += '<defs>$d</defs>';
  s += _r(100, 85, 120, 80, 'url(#${_uid(id, 'bg')})', 4, _sh, 2);
  s += _r(140, 78, 40, 12, _k, 2, _sh, 1);
  s += _line(105, 88, 215, 88, _sh, 1);
  s += _c(125, 115, 6, _k, _sh) + _c(125, 115, 3, '#3A3A4A');
  s += _c(145, 115, 4, _k);
  s += _r(170, 112, 16, 7, _k, 2);
  s += _led(115, 135, 2.5, _b);
  s += _r(130, 140, 60, 8, '#5A5A6A', 1, _sh, 1);
  s += _close();
  return s;
}

// ── Atari 2600 (stella) ──
String _atari(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#C0C0C0', '#808080');
  var s = _open('Atari 2600 wedge console with ridged top');
  s += '<defs>$d</defs>';
  s += _p('50,170 270,170 260,80 60,80', 'url(#${_uid(id, 'bg')})', _sh);
  for (var i = 0; i < 7; i++) {
    s += _line(70 + i * 28, 90, 60 + i * 28, 170, '#A0A0A0', 2);
  }
  for (var i = 0; i < 7; i++) {
    s += _line(70 + i * 28, 90, 60 + i * 28, 170, '#D0D0D0', 1,
        'opacity="0.5"');
  }
  s += _r(65, 135, 190, 30, _k, 0);
  s += _r(80, 142, 14, 10, '#3A3A3A', 2);
  s += _r(100, 142, 14, 10, '#3A3A3A', 2);
  s += _r(140, 144, 20, 6, '#4A4A4A', 1);
  s += _r(168, 144, 20, 6, '#4A4A4A', 1);
  s += _led(220, 150, 3, _b);
  for (final px in [70, 100, 130, 160, 190, 220]) {
    s += _r(px, 82, 20, 5, '#5A5A5A', 1);
  }
  s += _close();
  return s;
}

// ── Arcade (fbneo) ──
String _arcade(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#D0D4DC', '#9098A8');
  var s = _open('Arcade cabinet');
  s += '<defs>$d</defs>';
  s += _r(100, 20, 120, 220, 'url(#${_uid(id, 'bg')})', 4, _sh, 2);
  s += _r(105, 24, 110, 30, _k, 3);
  s += _r(110, 28, 100, 22, '#2A1A3A', 2);
  s += '<text x="160" y="43" text-anchor="middle" fill="$_bl" font-size="8" font-family="monospace" font-weight="bold" opacity="0.9">INSERT COIN</text>';
  s += _r(108, 58, 104, 80, _k, 4);
  s += _r(112, 62, 96, 72, _bd, 3);
  s += _r(116, 66, 88, 64, _b, 2);
  s += _r(106, 56, 108, 84, 'none', 4, _kl, 2);
  s += _r(95, 148, 130, 40, _s, 3, _sh, 1);
  s += _c(140, 165, 10, _k) + _c(140, 165, 7, _kl) + _c(140, 165, 3, '#4A4A5A');
  s += _r(138, 150, 4, 15, '#888888', 1);
  s += _c(140, 148, 5, '#CC3333');
  s += _c(175, 160, 6, '#CC3333', _k) +
      _c(190, 160, 6, '#3333CC', _k) +
      _c(205, 160, 6, '#33CC33', _k) +
      _c(175, 178, 6, '#CCCC33', _k) +
      _c(190, 178, 6, '#CC33CC', _k);
  s += _r(110, 195, 20, 12, _kl, 2, _sh, 1);
  s += _r(190, 195, 20, 12, _kl, 2, _sh, 1);
  s += _r(100, 230, 120, 8, _sd, 2, _sh, 1);
  s += _close();
  return s;
}

// ── DOSBox (dosbox_pure) ──
String _dosbox(String id) {
  final dc = _lg(_uid(id, 'crt'), 0, 100, '#C0C4CC', '#88909C');
  final dt = _lg(_uid(id, 'twr'), 0, 100, '#B8BCC4', '#7A8290');
  var s = _open('CRT monitor and PC tower');
  s += '<defs>$dc$dt</defs>';
  s += _r(30, 30, 140, 120, 'url(#${_uid(id, 'crt')})', 10, _sh, 2);
  s += _r(40, 40, 120, 90, _k, 6);
  s += _r(44, 44, 112, 82, '#1A1A2A', 4);
  s += _text(52, 60, 'C:\\&gt;dir', '#AAAAAA', 7);
  s += _text(52, 72, ' Volume in', '#AAAAAA', 6);
  s += _text(52, 84, 'DOSBOX EXE', '#CCCCCC', 6);
  s += _text(52, 96, 'COMMAND COM', '#AAAAAA', 6);
  s += _text(52, 110, 'C:\\&gt;_', '#AAAAAA', 7);
  s += _r(80, 135, 20, 6, '#4A4A5A', 2);
  s += _led(100, 142, 3, _b);
  s += _r(200, 50, 70, 170, 'url(#${_uid(id, 'twr')})', 3, _sh, 2);
  s += _r(208, 65, 54, 12, _k, 2, _sh, 1);
  s += _r(210, 67, 50, 8, '#2A2A34', 1);
  s += _line(212, 73, 256, 73, '#1A1A22', 1);
  s += _r(208, 85, 54, 10, _k, 2, _sh, 1);
  s += _r(210, 87, 20, 6, '#2A2A34', 1);
  s += _c(235, 120, 7, '#4A4A5A', _sh) + _c(235, 120, 4, '#3A3A4A');
  s += _led(235, 135, 2.5, _b);
  for (var i = 0; i < 4; i++) {
    s += _r(210, 148 + i * 10, 50, 3, '#6A7078', 1);
  }
  s += _c(235, 210, 8, _k, _sh) + _c(235, 210, 6, '#3A3A44');
  s += _close();
  return s;
}

// ── ScummVM (scummvm) ──
String _scummvm(String id) {
  final d = _lg(_uid(id, 'bg'), 0, 100, '#C8CCD4', '#8A90A0');
  var s = _open('ScummVM adventure game engine on CRT display');
  s += '<defs>$d</defs>';
  s += _r(50, 20, 220, 150, 'url(#${_uid(id, 'bg')})', 12, _sh, 2);
  s += _r(62, 32, 196, 110, _k, 6);
  s += _r(66, 36, 188, 102, '#1A1A2A', 4);
  s += _r(66, 36, 188, 70, '#1A0A2A', 0);
  s += _r(66, 106, 188, 32, '#0A2A0A', 0);
  s += _r(148, 80, 12, 16, '#AA8855', 2);
  s += _c(154, 76, 5, '#DDBB88');
  s += _r(144, 78, 4, 10, '#886644');
  s += _r(160, 78, 4, 10, '#886644');
  s += _r(150, 96, 4, 10, '#553322');
  s += _r(156, 96, 4, 10, '#553322');
  s += _r(70, 116, 180, 20, _k, 0);
  s += _text(76, 130, '&gt; open door_', '#CCCCCC', 8);
  s += '<rect x="70" y="40" width="50" height="50" rx="3" fill="#000000" fill-opacity="0.6"/>';
  s += _text(80, 52, 'Open', '#FFFFFF', 6, 'sans-serif');
  s += _text(80, 62, 'Close', '#FFFFFF', 6, 'sans-serif');
  s += _text(80, 72, 'Give', '#FFFFFF', 6, 'sans-serif');
  s += _text(80, 82, 'Pick up', '#FFFFFF', 6, 'sans-serif');
  s += _r(130, 155, 60, 8, '#4A4A5A', 2);
  s += _led(230, 158, 3, _b);
  s += _r(70, 116, 180, 2, _b, 0);
  s += _r(60, 180, 200, 30, '#B0B4BC', 3, _sh, 1);
  for (var i = 0; i < 12; i++) {
    s += _r(68 + i * 15, 185, 12, 8, '#D0D4D8', 1, '#90949C', 0.5);
  }
  for (var i = 0; i < 11; i++) {
    s += _r(75 + i * 15, 196, 12, 8, '#D0D4D8', 1, '#90949C', 0.5);
  }
  s += _r(110, 206, 80, 6, '#D0D4D8', 1, '#90949C', 0.5);
  s += _close();
  return s;
}

typedef _Renderer = String Function(String id);

const Map<String, _Renderer> _renderers = {
  'pocketbit': _gb,
  'gambatte': _gb,
  'advancebit': _gba,
  'nesbyte': _nes,
  'superfx': _snes,
  'rcp64': _n64,
  'dualscreen': _ds,
  'powercube': _dolphin,
  'geometry1': _ps1,
  'portcomp': _psp,
  'blastproc': _md,
  'twinsh': _saturn,
  'dreamarc': _dreamcast,
  'cardcon': _pce,
  'joystick': _atari,
  'coinbox': _arcade,
  'realmode': _dosbox,
  'pointclick': _scummvm,
};

/// Number of core-specific renderers (mirrors `hardwareArt.count`).
const hardwareArtCores = 18;

/// Returns the finalized hardware silhouette SVG for [coreId].
/// Unknown ids (e.g. hold cores) get the generic console card.
String hardwareSvg(String coreId) {
  final fn = _renderers[coreId];
  if (fn != null) return fn(coreId);
  return _open('$coreId hardware') +
      _r(80, 80, 160, 80, _s, 8, _sh, 2) +
      '<text x="160" y="125" text-anchor="middle" fill="$_bl" font-size="10" font-family="sans-serif">$coreId</text>' +
      _close();
}
