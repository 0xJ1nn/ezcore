import 'dart:io';

import '../models/core_manifest.dart';
import 'local_data_dir.dart';

/// BIOS presence report for one core.
class BiosReport {
  const BiosReport({
    required this.coreId,
    required this.required,
    required this.present,
    required this.missing,
    required this.systemDir,
  });

  final String coreId;
  final bool required;
  final List<String> present;
  final List<String> missing;
  final String systemDir;

  bool get satisfied => missing.isEmpty;

  /// Copy-pasteable user guidance; empty when satisfied or not required.
  String get guidance {
    if (!required || satisfied) return '';
    // A manifest entry may be a subdirectory (e.g. `pcsx2/bios`): name the
    // full expected location so the user knows exactly where the dump goes.
    final paths = missing
        .map((name) => name.contains('/') ? '$systemDir/$name' : name)
        .join(', ');
    return 'Missing BIOS for $coreId: $paths. '
        'Place your dumps at $systemDir (files stay on this device).';
  }
}

bool _defaultFileExists(String path) => File(path).existsSync();

/// A directory entry counts only when it contains at least one file, so an
/// empty `pcsx2/bios` folder does not satisfy a BIOS requirement.
bool _defaultDirHasFiles(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return false;
  return dir.listSync().any((entity) => entity is File);
}

/// Checks BIOS files against the core manifest.
///
/// Pure logic over injected [fileExists]/[dirHasFiles] plus a thin
/// dir-resolved wrapper, so unit tests never touch disk. The player gates
/// boot on [check]; the Systems dock displays the counts.
class BiosCheck {
  BiosCheck({
    LocalDataDirProvider? dirs,
    bool Function(String path)? fileExists,
    bool Function(String path)? dirHasFiles,
  })  : _dirs = dirs ?? PlatformLocalDataDirProvider(),
        _fileExists = fileExists ?? _defaultFileExists,
        _dirHasFiles = dirHasFiles ?? _defaultDirHasFiles;

  final LocalDataDirProvider _dirs;
  final bool Function(String path) _fileExists;
  final bool Function(String path) _dirHasFiles;

  static String systemDirOf(LocalDataDirProvider dirs) =>
      '${dirs.localDataDirPath()}/system';

  Future<BiosReport> check(CoreManifest manifest) async {
    final dir = systemDirOf(_dirs);
    if (!manifest.biosRequired || manifest.biosFiles.isEmpty) {
      return BiosReport(
        coreId: manifest.id,
        required: false,
        present: const [],
        missing: const [],
        systemDir: dir,
      );
    }
    final present = <String>[];
    final missing = <String>[];
    for (final file in manifest.biosFiles) {
      if (_fileExists('$dir/$file') || _dirHasFiles('$dir/$file')) {
        present.add(file);
      } else {
        missing.add(file);
      }
    }
    return BiosReport(
      coreId: manifest.id,
      required: true,
      present: present,
      missing: missing,
      systemDir: dir,
    );
  }
}
