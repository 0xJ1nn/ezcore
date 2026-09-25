import 'package:flutter/material.dart';

/// Selects unbranded hardware artwork by core identity or supported systems.
///
/// Known catalog cores keep custom artwork. New cores inherit the closest
/// hardware family from their manifest, so adding a core does not require
/// making another image. Unknown systems use a neutral retro-computer render.
String hardwareArtworkAsset(
  String coreId, {
  Iterable<String> systems = const <String>[],
}) {
  final id = coreId.toLowerCase();
  final direct = _directArtwork[id];
  if (direct != null) return _asset(direct);

  final normalized = systems
      .map(
        (system) => system.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
      )
      .toSet();

  String? family;
  if (_containsAny(normalized, const {'nds', 'ds', '3ds', 'nintendods'})) {
    family = 'dualscreen';
  } else if (_containsAny(normalized, const {
    'psp',
    'switch',
    'vita',
    'gamegear',
    'lynx',
    'ngp',
    'ngpc',
    'neogeopocket',
    'wonderswan',
    'pokemonmini',
    'virtualboy',
  })) {
    family = 'portcomp';
  } else if (_containsAny(normalized, const {'gba', 'gameboyadvance'})) {
    family = 'advancebit';
  } else if (_containsAny(normalized, const {'gbc', 'gameboycolor'})) {
    family = 'gambatte';
  } else if (_containsAny(normalized, const {'gb', 'gameboy'})) {
    family = 'pocketbit';
  } else if (_containsAny(normalized, const {
    'psx',
    'ps1',
    'ps2',
    'playstation',
    'playstation2',
  })) {
    family = 'geometry1';
  } else if (_containsAny(normalized, const {'n64', 'nintendo64'})) {
    family = 'rcp64';
  } else if (_containsAny(normalized, const {
    'arcade',
    'neogeo',
    'mame',
    'fbneo',
  })) {
    family = 'coinbox';
  } else if (_containsAny(normalized, const {'scumm', 'scummvm', 'amiga'})) {
    family = 'pointclick';
  } else if (_containsAny(normalized, const {
    'dos',
    'pc',
    'msdos',
    'windows',
    'c64',
    'commodore64',
    'msx',
    'zxspectrum',
    'amstradcpc',
    'apple2',
    'atari8bit',
  })) {
    family = 'realmode';
  } else if (_containsAny(normalized, const {'atari2600', 'a2600', 'atari'})) {
    family = 'joystick';
  } else if (_containsAny(normalized, const {'gc', 'gamecube', 'wii'})) {
    family = 'powercube';
  } else if (_containsAny(normalized, const {
    'dc',
    'dreamcast',
    'naomi',
    '3do',
  })) {
    family = 'dreamarc';
  } else if (_containsAny(normalized, const {
    'saturn',
    'segasaturn',
    'sega32x',
  })) {
    family = 'twinsh';
  } else if (_containsAny(normalized, const {
    'pce',
    'tg16',
    'turbografx16',
    'pcecd',
  })) {
    family = 'cardcon';
  } else if (_containsAny(normalized, const {
    'genesis',
    'megadrive',
    'sms',
    'gg',
    'sg1000',
    'scd',
  })) {
    family = 'blastproc';
  } else if (_containsAny(normalized, const {'snes', 'supernes'})) {
    family = 'superfx';
  } else if (_containsAny(normalized, const {'nes', 'fds', 'famicom'})) {
    family = 'nesbyte';
  }

  return _asset(family ?? 'generic');
}

const _directArtwork = <String, String>{
  'pocketbit': 'pocketbit',
  'gambatte': 'gambatte',
  'advancebit': 'advancebit',
  'nesbyte': 'nesbyte',
  'superfx': 'superfx',
  'blastproc': 'blastproc',
  'joystick': 'joystick',
  'realmode': 'realmode',
  'cardcon': 'cardcon',
  'geometry1': 'geometry1',
  'rcp64': 'rcp64',
  'dualscreen': 'dualscreen',
  'portcomp': 'portcomp',
  'dreamarc': 'dreamarc',
  'powercube': 'powercube',
  'twinsh': 'twinsh',
  'coinbox': 'coinbox',
  'pointclick': 'pointclick',
};

String _asset(String name) => 'assets/core_art/$name.webp';

bool _containsAny(Set<String> systems, Set<String> candidates) =>
    systems.any(candidates.contains);

/// Project-generated product renders used in the perspective core carousel.
///
/// The transparent WebP files keep their background, so the existing carousel
/// perspective/scroll transform moves the complete device render. Missing or
/// corrupt assets fail visibly; the release gate decodes every file.
class CoreArtwork extends StatelessWidget {
  const CoreArtwork({
    super.key,
    required this.coreId,
    this.systems = const <String>[],
    this.fit = BoxFit.contain,
  });

  final String coreId;
  final List<String> systems;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      hardwareArtworkAsset(coreId, systems: systems),
      fit: fit,
      filterQuality: FilterQuality.high,
      // The largest card is about 300 logical pixels; cap decode memory
      // instead of retaining every 1024px catalog image at full size.
      cacheWidth: 640,
      excludeFromSemantics: true,
    );
  }
}
