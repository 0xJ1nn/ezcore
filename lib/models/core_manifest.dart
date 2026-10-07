/// A versioned, signed emulator-core plugin descriptor.
///
/// Mirrors `cores/<id>/manifest.json`. Validation rules live in [validate]
/// so both the app and CI can reject malformed or policy-breaking manifests
/// (e.g. downloadable executable code on iOS).
class CoreManifest {
  const CoreManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.license,
    required this.systems,
    required this.extensions,
    required this.cheatFamilies,
    required this.cheatsSupported,
    required this.delivery,
    required this.artifacts,
    this.homepage = '',
    this.biosRequired = false,
    this.biosFiles = const [],
    this.blockedReason = '',
    this.execution = const {},
    this.defaultOptions = const {},
    this.defaultOptionsErrors = const [],
    this.systemData = const [],
    this.systemDataErrors = const [],
  });

  final String id;
  final String name;
  final String version;
  final String license;
  final List<String> systems;
  final List<String> extensions;
  final List<String> cheatFamilies;
  final bool cheatsSupported;
  final Map<String, String> delivery; // os -> 'bundled' | 'download' | 'absent'
  final Map<String, String> artifacts; // 'platform-arch' -> sha256
  final String homepage;
  final bool biosRequired;
  final List<String> biosFiles;
  final String blockedReason;

  /// Platform execution strategy: os -> 'interpreter' | 'dynarec'.
  /// Absent entries mean 'unknown'. iOS must never resolve to dynarec.
  final Map<String, String> execution;

  /// Recommended starting values for this core's own options
  /// (`default_options`): option key -> value. Data only. They sit below the
  /// user's per-core and per-game choices (AppState.coreOptionsFor).
  final Map<String, String> defaultOptions;

  /// Problems found while parsing `default_options`; surfaced by [validate].
  final List<String> defaultOptionsErrors;

  /// The core's own data folders for the system dir (`system_data`, ADR-021),
  /// e.g. `["dolphin-emu"]`. Shipped under `system/<name>/` in the package.
  final List<String> systemData;

  /// Problems found while parsing `system_data`; surfaced by [validate].
  final List<String> systemDataErrors;

  /// Caps on `default_options`, shared with the package validator.
  static const int maxDefaultOptions = 128;
  static const int maxDefaultOptionLength = 256;

  bool get blocked => blockedReason.isNotEmpty;


  /// Parses a raw `default_options` value strictly: only string keys with
  /// string values are kept, nothing is stringified, and every problem is
  /// reported. Shared with the package validator so both apply one rule.
  static ({Map<String, String> options, List<String> errors})
  parseDefaultOptions(dynamic raw) {
    if (raw == null) return (options: const {}, errors: const []);
    if (raw is! Map) {
      return (
        options: const {},
        errors: const ['"default_options" must be an object'],
      );
    }
    final errors = <String>[];
    final options = <String, String>{};
    if (raw.length > maxDefaultOptions) {
      errors.add(
        '"default_options" has ${raw.length} entries (max $maxDefaultOptions)',
      );
    }
    for (final e in raw.entries) {
      final k = e.key, v = e.value;
      if (k is! String || v is! String) {
        errors.add('default_options entry "$k" must be a string value');
        continue;
      }
      if (k.isEmpty ||
          k.length > maxDefaultOptionLength ||
          v.length > maxDefaultOptionLength) {
        errors.add(
          'default_options entry "$k" is empty or longer than '
          '$maxDefaultOptionLength characters',
        );
        continue;
      }
      options[k] = v;
    }
    return (options: options, errors: errors);
  }

  /// Cap on `system_data` entries (ADR-021).
  static const maxSystemDataEntries = 4;
  static final _systemDataName = RegExp(r'^[A-Za-z0-9._-]+$');

  /// Parses a raw `system_data` value strictly: a short list of plain folder
  /// names. Returns the names (empty when absent) and any errors.
  static ({List<String> names, List<String> errors}) parseSystemData(
    Object? raw,
  ) {
    if (raw == null) return (names: const [], errors: const []);
    if (raw is! List) {
      return (
        names: const [],
        errors: const ['"system_data" must be a list of folder names'],
      );
    }
    final errors = <String>[];
    final names = <String>[];
    if (raw.length > maxSystemDataEntries) {
      errors.add(
        '"system_data" has ${raw.length} entries (max $maxSystemDataEntries)',
      );
    }
    for (final v in raw) {
      if (v is! String || !_systemDataName.hasMatch(v) || v == '.' || v == '..') {
        errors.add('"system_data" entry "$v" is not a plain folder name');
      } else if (names.contains(v)) {
        errors.add('"system_data" repeats "$v"');
      } else {
        names.add(v);
      }
    }
    return (names: names, errors: errors);
  }

  factory CoreManifest.fromJson(Map<String, dynamic> json) {
    final defaults = parseDefaultOptions(json['default_options']);
    final systemData = parseSystemData(json['system_data']);
    return CoreManifest(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: json['version'] as String? ?? '',
      license: json['license'] as String? ?? '',
      systems: _strList(json['systems']),
      extensions: _strList(json['extensions']),
      cheatFamilies: _strList(json['cheat_families']),
      cheatsSupported: json['cheats_supported'] as bool? ?? false,
      delivery: _strMap(json['delivery']),
      artifacts: _strMap(json['artifacts']),
      homepage: json['homepage'] as String? ?? '',
      biosRequired: json['bios_required'] as bool? ?? false,
      biosFiles: _biosNames(json['bios_files']),
      blockedReason: json['blocked_reason'] as String? ?? '',
      execution: _strMap(json['execution']),
      defaultOptions: defaults.options,
      defaultOptionsErrors: defaults.errors,
      systemData: systemData.names,
      systemDataErrors: systemData.errors,
    );
  }

  /// BIOS entries are filenames. Manifests may carry a human note in
  /// parentheses after the name (e.g. `sega_101.bin (user-supplied)`) —
  /// the app checks for real files on disk, so keep only the bare name.
  static List<String> _biosNames(dynamic v) => _strList(v)
      .map((e) {
        final i = e.indexOf(' (');
        return (i > 0 ? e.substring(0, i) : e).trim();
      })
      .where((e) => e.isNotEmpty)
      .toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'license': license,
        'systems': systems,
        'extensions': extensions,
        'cheat_families': cheatFamilies,
        'cheats_supported': cheatsSupported,
        'delivery': delivery,
        'delivery_note':
            'ios must be bundled or absent — never download (App Review 2.5.2/4.7)',
        'artifacts': artifacts,
        'homepage': homepage,
        'bios_required': biosRequired,
        'bios_files': biosFiles,
        if (blockedReason.isNotEmpty) 'blocked_reason': blockedReason,
        if (execution.isNotEmpty) 'execution': execution,
        if (defaultOptions.isNotEmpty) 'default_options': defaultOptions,
        if (systemData.isNotEmpty) 'system_data': systemData,
      };

  /// Returns human-readable policy errors. Empty = valid.
  List<String> validate() {
    final errors = <String>[];
    if (id.isEmpty) errors.add('missing id');
    if (name.isEmpty) errors.add('missing name');
    if (version.isEmpty) errors.add('missing version');
    if (license.isEmpty) errors.add('missing license');
    if (systems.isEmpty) errors.add('no systems');
    if (extensions.isEmpty && !blocked) errors.add('no extensions');
    if (delivery['ios'] == 'download') {
      errors.add('ios delivery must be bundled or absent, never download');
    }
    if (blocked && artifacts.isNotEmpty) {
      errors.add('blocked core must not ship artifacts');
    }
    errors.addAll(defaultOptionsErrors);
    errors.addAll(systemDataErrors);
    for (final entry in execution.entries) {
      if (entry.value != 'interpreter' && entry.value != 'dynarec') {
        errors.add('bad execution strategy for ${entry.key}');
      }
      if (entry.key == 'ios' && entry.value == 'dynarec') {
        errors.add('ios must never use dynarec (no JIT on App Store)');
      }
    }
    return errors;
  }

  /// Execution strategy for [os], or 'unknown' when undeclared.
  String executionFor(String os) => execution[os] ?? 'unknown';

  static List<String> _strList(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  static Map<String, String> _strMap(dynamic v) => v is Map
      ? v.map((k, val) => MapEntry(k.toString(), val.toString()))
      : const {};
}
