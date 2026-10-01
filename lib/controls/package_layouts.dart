import 'dart:convert';
import 'dart:io';

import 'control_layout.dart';

/// On-screen layouts shipped inside a core package (ADR-020): the package's
/// `layouts/` folder, staged to `<cores>/<id>/layouts/` on install.
///
/// One set of rules, used by the package validator before install and by the
/// loader at play time, so the two can never disagree:
///  - flat: only `.json` files, no folders, no links;
///  - at most [maxPackageLayouts] files of at most [maxLayoutBytes] each;
///  - every file is a valid `ezcore.controls/1` layout with a unique id;
///  - a layout may only target systems the package's own manifest declares,
///    so a third-party core cannot replace another system's controls.
const maxPackageLayouts = 32;
const maxLayoutBytes = 64 * 1024;

/// Reads and checks [dir]. A missing folder is simply no layouts.
({List<(String file, ControlLayout layout)> layouts, List<String> errors})
readLayoutDir(Directory dir, {required List<String> allowedSystems}) {
  final errors = <String>[];
  final out = <(String, ControlLayout)>[];
  if (!dir.existsSync()) return (layouts: out, errors: errors);
  final entries = dir.listSync(followLinks: false)
    ..sort((a, b) => a.path.compareTo(b.path));
  final files = <File>[];
  for (final e in entries) {
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (e is Link) {
      errors.add('layouts/$name: links are not allowed');
    } else if (e is Directory) {
      errors.add('layouts/$name: folders are not allowed inside layouts/');
    } else if (e is File && name.endsWith('.json')) {
      files.add(e);
    } else {
      errors.add('layouts/$name: only .json files are allowed');
    }
  }
  if (files.length > maxPackageLayouts) {
    errors.add('layouts/ has ${files.length} files (max $maxPackageLayouts)');
    return (layouts: out, errors: errors);
  }
  final ids = <String>{};
  for (final f in files) {
    final name = f.uri.pathSegments.last;
    if (f.lengthSync() > maxLayoutBytes) {
      errors.add('layouts/$name is larger than $maxLayoutBytes bytes');
      continue;
    }
    Object? json;
    try {
      json = jsonDecode(f.readAsStringSync());
    } catch (e) {
      errors.add('layouts/$name is not valid JSON');
      continue;
    }
    final r = ControlLayout.parse(json);
    if (r.layout == null) {
      errors.addAll(r.errors.map((m) => 'layouts/$name: $m'));
      continue;
    }
    final layout = r.layout!;
    final foreign =
        layout.systems.where((s) => !allowedSystems.contains(s)).toList();
    if (foreign.isNotEmpty) {
      errors.add(
        'layouts/$name targets ${foreign.join(', ')}, which this core does '
        'not declare',
      );
      continue;
    }
    if (!ids.add(layout.id)) {
      errors.add('layouts/$name repeats layout id "${layout.id}"');
      continue;
    }
    out.add((name, layout));
  }
  return (layouts: out, errors: errors);
}

/// Installed packages' layouts, read once per core and kept, so the player
/// (which asks every frame) always gets the same instances.
class PackageLayouts {
  PackageLayouts(this._coresRoot);

  /// The directory holding `<id>/` core folders (the vault).
  final String? Function() _coresRoot;
  final Map<String, List<ControlLayout>> _cache = {};

  /// The installed package's layout for [system] in this orientation, if it
  /// ships one. An exact orientation wins over an `any` layout.
  ControlLayout? layoutFor(String coreId, String system, {required bool portrait}) {
    final want = portrait ? LayoutOrientation.portrait : LayoutOrientation.landscape;
    final mine = _layouts(coreId).where((l) => l.systems.contains(system));
    return mine.where((l) => l.orientation == want).firstOrNull ??
        mine.where((l) => l.orientation == LayoutOrientation.any).firstOrNull;
  }

  /// Forget cached layouts (after installing or removing a core).
  void invalidate() => _cache.clear();

  List<ControlLayout> _layouts(String coreId) => _cache.putIfAbsent(coreId, () {
    final root = _coresRoot();
    if (root == null) return const [];
    final dir = Directory('$root/$coreId');
    final manifest = File('${dir.path}/manifest.json');
    if (!manifest.existsSync()) return const [];
    List<String> systems;
    try {
      final m = jsonDecode(manifest.readAsStringSync()) as Map;
      systems = [for (final s in (m['systems'] as List? ?? const [])) '$s'];
    } catch (_) {
      return const [];
    }
    final r = readLayoutDir(
      Directory('${dir.path}/layouts'),
      allowedSystems: systems,
    );
    // Re-checked at load: only layouts that still pass every rule are used.
    return [for (final (_, l) in r.layouts) l];
  });
}
