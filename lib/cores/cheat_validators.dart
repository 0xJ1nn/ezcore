/// Syntax validators for per-system cheat code families.
///
/// These check *format* only (hex shape, grouping) plus a bridge dry-run
/// hook — they never execute codes. Samples in tests are hand-written
/// patterns, never copied from commercial cheat databases.
abstract final class CheatValidators {
  static final Map<String, List<RegExp>> _patterns = {
    // Game Boy / Game Boy Color
    'gb_gameshark': [RegExp(r'^[0-9A-Fa-f]{8}$')],
    'gb_gamegenie': [RegExp(r'^[0-9A-Fa-f]{3}-[0-9A-Fa-f]{3}(-[0-9A-Fa-f]{3})?$')],
    // Game Boy Advance
    'gba_actionreplay': [RegExp(r'^[0-9A-Fa-f]{16}$')],
    'gba_codebreaker': [RegExp(r'^[0-9A-Fa-f]{13}$')],
    'gba_gameshark': [RegExp(r'^[0-9A-Fa-f]{16}$')],
    // SNES
    'snes_gamegenie': [
      RegExp(r'^[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}$'),
      RegExp(r'^[0-9A-Fa-f]{9}$'),
    ],
    'snes_proactionreplay': [RegExp(r'^[0-9A-Fa-f]{8}$')],
    // Genesis / Mega Drive
    'genesis_gamegenie': [RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}$')],
    'genesis_actionreplay': [RegExp(r'^[0-9A-Fa-f]{10}$')],
    // PlayStation
    'ps1_gameshark': [RegExp(r'^[0-9A-Fa-f]{12}$')],
    // Sega Saturn (Mednafen GameShark: 8+4 hex pairs, + joined in .cht DBs)
    'saturn_gameshark': [RegExp(r'^[0-9A-Fa-f]{12}$')],
    // Nintendo 64
    'n64_gameshark': [RegExp(r'^[0-9A-Fa-f]{12}$')],
    // NES
    'nes_gamegenie': [RegExp(r'^[A-Z]{4}-[A-Z]{4}$')],
    // Master System / Game Gear
    'sms_actionreplay': [RegExp(r'^[0-9A-Fa-f]{9}$')],
    // Dreamcast
    'dc_codebreaker': [RegExp(r'^[0-9A-Fa-f]{12}$')],
    // PSP (CWCheat style _C0 lines)
    'psp_cwcheat': [RegExp(r'^_C0?\s+.+'), RegExp(r'^_L\s+0x[0-9A-Fa-f]+\s+0x[0-9A-Fa-f]+')],
    // DS (Action Replay DS)
    'nds_actionreplay': [RegExp(r'^[0-9A-Fa-f]{16}$')],
    // GameCube (Gecko / Action Replay)
    'gc_gecko': [RegExp(r'^[0-9A-Fa-f]{16}$')],
  };

  /// All known family ids (sourced from installed core manifests at runtime).
  static List<String> get families => _patterns.keys.toList()..sort();

  /// Returns error text, or null when every non-empty line of [code]
  /// matches at least one pattern of [family]. Unknown families fail closed.
  ///
  /// Lines may join multiple codes with `+` (the libretro-database `.cht`
  /// convention, also produced by [joinCheatCode]): each `+`-separated
  /// segment must then be a 4/8-hex GameShark-style chunk (wildcards `?`
  /// allowed, matching DB joker codes like `D00ABA60+????`).
  static String? validate(String family, String code) {
    final patterns = _patterns[family];
    if (patterns == null) return 'Unknown cheat family: $family';
    final lines =
        code.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    if (lines.isEmpty) return 'Code is empty';
    var lineNo = 0;
    for (final line in lines) {
      lineNo++;
      if (_matchesLine(patterns, line)) continue;
      return 'Line $lineNo is not a valid $family code';
    }
    return null;
  }

  static final RegExp _multiSegment = RegExp(r'^[0-9A-Fa-f?]{4}$|^[0-9A-Fa-f?]{8}$');

  static bool _matchesLine(List<RegExp> patterns, String line) {
    final normalized = line.replaceAll(' ', '');
    if (patterns.any((p) => p.hasMatch(line) || p.hasMatch(normalized))) {
      return true;
    }
    if (!normalized.contains('+')) return false;
    final segments = normalized.split('+').where((s) => s.isNotEmpty);
    if (segments.isEmpty) return false;
    return segments.every((s) => _multiSegment.hasMatch(s));
  }
}
