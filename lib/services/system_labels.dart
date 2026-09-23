/// Human-readable labels for system IDs.
///
/// Sourced from core manifest `systems` entries and common shorthand.
/// Purely a display concern — never used for core matching logic.
const systemLabels = <String, String>{
  'gb': 'Game Boy',
  'gbc': 'Game Boy Color',
  'gba': 'Game Boy Advance',
  'snes': 'Super Nintendo',
  'nds': 'Nintendo DS',
  'psx': 'PlayStation',
  'psp': 'PlayStation Portable',
  'gc': 'GameCube',
  'dos': 'DOS',
  'nes': 'Nintendo Entertainment System',
  'genesis': 'Genesis / Mega Drive',
  'n64': 'Nintendo 64',
  'dc': 'Dreamcast',
  'atari2600': 'Atari 2600',
  'pce': 'PC Engine / TurboGrafx-16',
  'tg16': 'TurboGrafx-16',
  'pcecd': 'PC Engine CD',
  'saturn': 'Saturn',
  'arcade': 'Arcade',
  'neogeo': 'Neo Geo',
  'sms': 'Master System',
  'gg': 'Game Gear',
  'sg1000': 'SG-1000',
  'scd': 'Mega CD',
  'scumm': 'SCUMM',
  '3ds': 'Nintendo 3DS',
  'switch': 'Nintendo Switch',
  'ps2': 'PlayStation 2',
  'wii': 'Wii',
  'naomi': 'NAOMI',
  'fds': 'Famicom Disk System',
};

/// Short labels for compact surfaces (pickers, chip rows, tile corners).
/// Long labels stay for headers where the full name reads better.
const systemShortLabels = <String, String>{
  'gb': 'Game Boy',
  'gbc': 'Game Boy Color',
  'gba': 'Game Boy Advance',
  'snes': 'SNES',
  'nds': 'Nintendo DS',
  'psx': 'PlayStation',
  'psp': 'PSP',
  'gc': 'GameCube',
  'dos': 'DOS',
  'nes': 'NES',
  'genesis': 'Genesis',
  'n64': 'Nintendo 64',
  'dc': 'Dreamcast',
  'atari2600': 'Atari 2600',
  'pce': 'PC Engine',
  'tg16': 'TurboGrafx-16',
  'pcecd': 'PC Engine CD',
  'saturn': 'Saturn',
  'arcade': 'Arcade',
  'neogeo': 'Neo Geo',
  'sms': 'Master System',
  'gg': 'Game Gear',
  'sg1000': 'SG-1000',
  'scd': 'Mega CD',
  'scumm': 'SCUMM',
  '3ds': 'Nintendo 3DS',
  'switch': 'Nintendo Switch',
  'ps2': 'PlayStation 2',
  'wii': 'Wii',
  'naomi': 'NAOMI',
  'fds': 'Famicom Disk',
};

/// Manufacturer grouping, so the system picker can show the plate's
/// Nintendo / Sega / Other sections.
const systemMakers = <String, String>{
  'gb': 'Nintendo',
  'gbc': 'Nintendo',
  'gba': 'Nintendo',
  'snes': 'Nintendo',
  'nds': 'Nintendo',
  'n64': 'Nintendo',
  'nes': 'Nintendo',
  'fds': 'Nintendo',
  'sg1000': 'Nintendo',
  'genesis': 'Sega',
  'sms': 'Sega',
  'gg': 'Sega',
  'scd': 'Sega',
  'saturn': 'Sega',
  'dc': 'Sega',
  'naomi': 'Sega',
  'psx': 'Sony',
  'psp': 'Sony',
  'ps2': 'Sony',
  'atari2600': 'Atari',
  'pce': 'NEC',
  'tg16': 'NEC',
  'pcecd': 'NEC',
  'gc': 'Nintendo',
  'wii': 'Nintendo',
};

/// Section order for the picker; unknown makers land in `Other`.
const systemMakerOrder = <String>[
  'Nintendo',
  'Sega',
  'Sony',
  'Atari',
  'NEC',
  'PC',
  'Other',
];

/// Manufacturer for [system], defaulting to `Other`.
String makerFor(String system) => systemMakers[system] ?? 'Other';

/// Compact label for [system].
String shortSystemLabel(String system) =>
    systemShortLabels[system] ?? systemLabels[system] ?? system;
