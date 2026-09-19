import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'test_paths.dart' as paths;

/// Subprocess-driven core matrix.
///
/// Each staged core boots inside the fork-isolated native harness
/// (`runtime/test/test_core_boot`), so a crashing core fails its own case
/// and never the suite — the failure mode that retired `all_cores_test`
/// in-process loading. Levels per core:
/// - full boot + 30 frames + pixels + save/restore + cheats + audio drain
///   where a fixture ROM exists (see [_fullBoot]);
/// - load + init + identify where no fixture exists.
///
/// Cores without a staged artifact for this host (holds, unbuilt
/// platforms) skip individually.
String? _harness() {
  final dir = paths.runtimeBuildDir();
  if (dir == null) return null;
  final exe =
      Platform.isWindows ? 'test_core_boot.exe' : 'test_core_boot';
  final candidate = '$dir/$exe';
  return File(candidate).existsSync() ? candidate : null;
}

String? _artifact(String id) => paths.stagedCoreLib(id);

List<String> _catalogIds() {
  final ids = <String>[];
  final dir = Directory('cores');
  if (!dir.existsSync()) return ids;
  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;
    final manifest = File('${entity.path}/manifest.json');
    if (!manifest.existsSync()) continue;
    try {
      final json =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      if ((json['blocked_reason'] as String? ?? '').isEmpty) {
        ids.add(json['id'] as String? ?? entity.uri.pathSegments.last);
      }
    } catch (_) {}
  }
  return ids..sort();
}

/// Fixture ROMs (public-domain / test-suite content under test/fixtures
/// once sourced; local-only paths until then — see docs/MATRIX.md).
const _fullBoot = {
  'pocketbit': 'native/test-roms/cpu_instrs.gb',
  'gambatte': 'native/test-roms/cpu_instrs.gb',
  'advancebit': 'native/test-roms/test.gba',
  'nesbyte': 'native/test-roms/ezcore_nes_minimal.nes',
};

void main() {
  final harness = _harness();
  if (harness == null) {
    test('core matrix harness', () {
      markTestSkipped('native harness not built (scripts/build_runtime.sh)');
    });
    return;
  }

  for (final id in _catalogIds()) {
    test('matrix $id', () async {
      final lib = _artifact(id);
      if (lib == null) {
        markTestSkipped('no staged artifact for $id on this host');
        return;
      }
      final rom = _fullBoot[id];
      final args = (rom != null && File(rom).existsSync())
          ? [lib, rom]
          : [lib, '--identify-only'];
      final result = await Process.run(harness, args);
      expect(
        result.exitCode,
        0,
        reason: '$id [${args.length == 2 && args[1] != '--identify-only' ? 'full' : 'identify'}]\n'
            '${result.stdout}\n${result.stderr}',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
