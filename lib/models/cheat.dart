/// RetroArch-compatible `.cht` cheat file model.
///
/// Canonical on-disk format (sections per code). Nothing cheat-related
/// ships with the app — files are user-created, user-imported, or fetched
/// by explicit opt-in from the libretro-database community source.
class CheatEntry {
  const CheatEntry({
    required this.index,
    required this.desc,
    required this.code,
    this.enabled = false,
  });

  final int index;
  final String desc;
  final String code;
  final bool enabled;

  CheatEntry toggled() =>
      CheatEntry(index: index, desc: desc, code: code, enabled: !enabled);

  CheatEntry edited({String? desc, String? code}) => CheatEntry(
        index: index,
        desc: desc ?? this.desc,
        code: code ?? this.code,
        enabled: enabled,
      );
}

/// Parses `.cht` text into entries. Tolerates missing fields; skips
/// sections without any `code` line.
List<CheatEntry> parseCht(String text) {
  final entries = <CheatEntry>[];
  var index = -1;
  var desc = '';
  final codes = <String>[];
  var enabled = false;

  void flush() {
    if (index >= 0 && codes.isNotEmpty) {
      entries.add(CheatEntry(
        index: index,
        desc: desc.isEmpty ? 'Cheat $index' : desc,
        code: codes.join('\n'),
        enabled: enabled,
      ));
    }
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final section = RegExp(r'^\[cheat(\d+)\]$').firstMatch(line);
    if (section != null) {
      flush();
      index = int.parse(section.group(1)!);
      desc = '';
      codes.clear();
      enabled = false;
      continue;
    }
    final kv = line.indexOf('=');
    if (kv < 0) continue;
    final key = line.substring(0, kv).trim();
    final value = line.substring(kv + 1).trim().replaceAll('"', '');
    switch (key) {
      case 'desc':
        desc = value;
      case 'code':
        codes.add(value);
      case 'enable':
        enabled = value.toLowerCase() == 'true' || value == '1';
    }
  }
  flush();
  return entries;
}

/// Serializes entries back to `.cht` text (round-trips [parseCht]).
String serializeCht(List<CheatEntry> entries) {
  final out = StringBuffer('cheats = ${entries.length}\n\n');
  for (final e in entries) {
    out.writeln('[cheat${e.index}]');
    out.writeln('desc = "${e.desc}"');
    for (final line in e.code.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) out.writeln('code = "$trimmed"');
    }
    out.writeln('enable = ${e.enabled}\n');
  }
  return out.toString();
}
