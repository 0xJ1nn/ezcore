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

  factory CoreManifest.fromJson(Map<String, dynamic> json) {
    final defaults = parseDefaultOptions(json['default_options']);
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
