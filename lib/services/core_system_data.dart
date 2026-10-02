import 'dart:io';
import 'dart:typed_data';

/// Core system data (ADR-021): a core's own non-executable program data —
/// Dolphin's `dolphin-emu/Sys`, PPSSPP's `PPSSPP` assets — shipped in the
/// core package under `system/<name>/` and copied into the libretro system
/// directory, where the core looks for it.
///
/// It is the core's data (same licence as the core), never BIOS, firmware or
/// keys: those stay user-supplied. One set of rules, used by the package
/// validator, by staging and before every session, so they cannot disagree:
///  - the manifest declares every top-level name (`system_data`); the
///    package's `system/` holds exactly those, no more, no fewer;
///  - no links, no file with an execute bit, no file that starts like an
///    executable or a script;
///  - capped in size and file count;
///  - no name may be one of the manifest's BIOS files.
const maxSystemDataBytes = 128 * 1024 * 1024;
const maxSystemDataFiles = 20000;

/// Written last into each copied folder: `<coreId> <version>`. A folder
/// without it was made by someone else and is never touched.
const systemDataMarker = '.ezcore-system-data';

/// Validates `<package>/system`. A missing folder with nothing declared is
/// fine; declared names without the folder are an error unless
/// [requirePresent] is false (the validator, which also checks manifest-only
/// folders such as the repository's `cores/<id>/`; copying always requires
/// the data).
({int files, int bytes, List<String> errors}) checkSystemData(
  Directory systemDir, {
  required List<String> declared,
  List<String> biosFiles = const [],
  int maxBytes = maxSystemDataBytes,
  int maxFiles = maxSystemDataFiles,
  bool requirePresent = true,
}) {
  final errors = <String>[];
  if (!systemDir.existsSync()) {
    if (!requirePresent) return (files: 0, bytes: 0, errors: errors);
    for (final n in declared) {
      errors.add('system_data declares "$n" but system/$n is missing');
    }
    return (files: 0, bytes: 0, errors: errors);
  }
  final top = <String>{};
  for (final e in systemDir.listSync(followLinks: false)) {
    final name = _base(e.path);
    if (e is Link) {
      errors.add('system/$name: links are not allowed');
    } else if (e is! Directory) {
      errors.add('system/$name: only the declared folders may sit in system/');
    } else if (!declared.contains(name)) {
      errors.add('system/$name is not declared in system_data');
    } else {
      top.add(name);
    }
  }
  for (final n in declared) {
    if (!top.contains(n)) errors.add('system_data declares "$n" but system/$n is missing');
  }
  final bios = biosFiles.map((b) => b.toLowerCase()).toSet();
  var files = 0;
  var bytes = 0;
  for (final n in top) {
    for (final e in Directory('${systemDir.path}/$n').listSync(recursive: true, followLinks: false)) {
      final rel = e.path.substring(systemDir.path.length + 1);
      if (e is Link) {
        errors.add('system/$rel: links are not allowed');
        continue;
      }
      if (bios.contains(_base(e.path).toLowerCase())) {
        errors.add('system/$rel has the name of a BIOS file; BIOS is never shipped');
      }
      if (e is! File) continue;
      files++;
      final stat = e.statSync();
      bytes += stat.size;
      if (stat.mode & 0x49 != 0) {
        errors.add('system/$rel is executable; system data must be data only');
      } else if (_looksExecutable(e)) {
        errors.add('system/$rel starts like a program or script; system data must be data only');
      }
    }
  }
  if (files > maxFiles) errors.add('system/ has $files files (max $maxFiles)');
  if (bytes > maxBytes) errors.add('system/ is $bytes bytes (max $maxBytes)');
  return (files: files, bytes: bytes, errors: errors);
}

/// Copies each declared `<from>/<name>` to `<to>/<name>` unless `<to>/<name>`
/// already carries this core version's marker. Validates first (nothing is
/// copied when anything fails). Returns errors (nothing copied) and warnings
/// (a folder skipped because it is not ours).
Future<({List<String> errors, List<String> warnings})> copySystemData({
  required Directory from,
  required Directory to,
  required String coreId,
  required String version,
  required List<String> declared,
  List<String> biosFiles = const [],
}) async {
  if (declared.isEmpty) return (errors: const <String>[], warnings: const <String>[]);
  final check = checkSystemData(from, declared: declared, biosFiles: biosFiles);
  if (check.errors.isNotEmpty) return (errors: check.errors, warnings: const <String>[]);
  final stamp = '$coreId $version\n';
  final warnings = <String>[];
  for (final n in declared) {
    final dest = Directory('${to.path}/$n');
    final marker = File('${dest.path}/$systemDataMarker');
    if (marker.existsSync() && marker.readAsStringSync() == stamp) continue;
    if (dest.existsSync() && !marker.existsSync()) {
      warnings.add('${dest.path} exists and was not made by ezCORE; left as it is');
      continue;
    }
    if (dest.existsSync()) await dest.delete(recursive: true); // an older copy of ours
    await _copyTree(Directory('${from.path}/$n'), dest);
    await marker.writeAsString(stamp);
  }
  return (errors: const <String>[], warnings: warnings);
}

Future<void> _copyTree(Directory src, Directory dest) async {
  await dest.create(recursive: true);
  await for (final e in src.list(recursive: true, followLinks: false)) {
    final rel = e.path.substring(src.path.length + 1);
    if (e is Directory) {
      await Directory('${dest.path}/$rel').create(recursive: true);
    } else if (e is File) {
      await File('${dest.path}/$rel').parent.create(recursive: true);
      await e.copy('${dest.path}/$rel');
    }
  }
}

String _base(String path) => path.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).last;

/// ELF, Mach-O (32/64, both byte orders, fat), PE ("MZ"), or a "#!" script.
bool _looksExecutable(File f) {
  Uint8List head;
  try {
    final raf = f.openSync();
    try {
      head = raf.readSync(4);
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return false;
  }
  bool starts(List<int> sig) {
    if (head.length < sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (head[i] != sig[i]) return false;
    }
    return true;
  }
  return starts([0x7F, 0x45, 0x4C, 0x46]) ||
      starts([0xFE, 0xED, 0xFA, 0xCE]) ||
      starts([0xFE, 0xED, 0xFA, 0xCF]) ||
      starts([0xCE, 0xFA, 0xED, 0xFE]) ||
      starts([0xCF, 0xFA, 0xED, 0xFE]) ||
      starts([0xCA, 0xFE, 0xBA, 0xBE]) ||
      starts([0x4D, 0x5A]) ||
      starts([0x23, 0x21]);
}
