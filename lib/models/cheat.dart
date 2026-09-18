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

  Map<String, dynamic> toJson() => {
        'index': index,
        'desc': desc,
        'code': code,
        'enabled': enabled,
      };

  factory CheatEntry.fromJson(Map<String, dynamic> json) => CheatEntry(
        index: json['index'] as int? ?? 0,
        desc: json['desc'] as String? ?? '',
        code: json['code'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CheatEntry &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          desc == other.desc &&
          code == other.code &&
          enabled == other.enabled;

  @override
  int get hashCode => Object.hash(index, desc, code, enabled);
}

/// Parses `.cht` text into entries. Tolerates missing fields; skips
/// sections without any `code` line.
///
/// Two layouts are accepted (identical semantics):
/// - bracket sections (`[cheat0]` … `desc`/`code`/`enable`), the historical
///   ezCORE authoring shape;
/// - flat keys (`cheat0_desc`, `cheat0_code`, `cheat0_enable`), the
///   libretro-database community format.
List<CheatEntry> parseCht(String text) {
  final sections = <int, _Draft>{};

  _Draft draft(int index) => sections.putIfAbsent(index, () => _Draft());

  var current = -1;
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final section = RegExp(r'^\[cheat(\d+)\]$').firstMatch(line);
    if (section != null) {
      current = int.parse(section.group(1)!);
      draft(current);
      continue;
    }
    final kv = line.indexOf('=');
    if (kv < 0) continue;
    final key = line.substring(0, kv).trim();
    final value = line.substring(kv + 1).trim().replaceAll('"', '');
    final flat = RegExp(r'^cheat(\d+)_(desc|code|enable)$').firstMatch(key);
    if (flat != null) {
      final d = draft(int.parse(flat.group(1)!));
      d.apply(flat.group(2)!, value);
      continue;
    }
    if (current < 0) continue;
    draft(current).apply(key, value);
  }
  final entries = <CheatEntry>[];
  for (final entry in sections.entries) {
    final d = entry.value;
    if (d.codes.isEmpty) continue;
    entries.add(CheatEntry(
      index: entry.key,
      desc: d.desc.isEmpty ? 'Cheat ${entry.key}' : d.desc,
      code: d.codes.join('\n'),
      enabled: d.enabled,
    ));
  }
  entries.sort((a, b) => a.index.compareTo(b.index));
  return entries;
}

class _Draft {
  var desc = '';
  final codes = <String>[];
  var enabled = false;

  void apply(String key, String value) {
    switch (key) {
      case 'desc':
        desc = value;
      case 'code':
        codes.add(value);
      case 'enable':
        enabled = value.toLowerCase() == 'true' || value == '1';
    }
  }
}

/// Joins editor-format multi-line codes into the single `+`-separated
/// string the libretro `cheat_set` call expects (matches RetroArch, which
/// appends multiple `code = ` lines with `+`).
String joinCheatCode(String code) => code
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .join('+');

/// Serializes entries to flat-key `.cht` text (the libretro-database
/// community layout), which [parseCht] round-trips.
String serializeCht(List<CheatEntry> entries) {
  final out = StringBuffer('cheats = ${entries.length}\n\n');
  for (final e in entries) {
    out.writeln('cheat${e.index}_desc = "${e.desc}"');
    for (final line in e.code.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        out.writeln('cheat${e.index}_code = "$trimmed"');
      }
    }
    out.writeln('cheat${e.index}_enable = ${e.enabled}\n');
  }
  return out.toString();
}
