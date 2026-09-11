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

  bool get blocked => blockedReason.isNotEmpty;

  factory CoreManifest.fromJson(Map<String, dynamic> json) {
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
      biosFiles: _strList(json['bios_files']),
      blockedReason: json['blocked_reason'] as String? ?? '',
    );
  }

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
    return errors;
  }

  static List<String> _strList(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? const [];

  static Map<String, String> _strMap(dynamic v) => v is Map
      ? v.map((k, val) => MapEntry(k.toString(), val.toString()))
      : const {};
}
