import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/core_manifest.dart';

/// Install state of a single core plugin.
enum CoreStatus { notInstalled, installed, updateAvailable, blocked }

/// Pure-logic core plugin registry: manifest index + install/remove/update.
///
/// Platform loaders (desktop dlopen, Android .so, iOS bundled) consume
/// [installedCores]; this class never touches native code so it stays
/// unit-testable.
class CoreRegistry extends ChangeNotifier {
  CoreRegistry();

  final Map<String, CoreManifest> _catalog = {};
  final Map<String, String> _installed = {}; // id -> version
  final Map<String, String> _artifactSha = {}; // id -> verified sha256

  List<CoreManifest> get catalog => _catalog.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  List<CoreManifest> get installedCores => _catalog.values
      .where((m) => _installed.containsKey(m.id))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  bool isInstalled(String id) => _installed.containsKey(id);

  CoreStatus statusOf(CoreManifest m) {
    if (m.blocked) return CoreStatus.blocked;
    final installed = _installed[m.id];
    if (installed == null) return CoreStatus.notInstalled;
    if (installed != m.version) return CoreStatus.updateAvailable;
    return CoreStatus.installed;
  }

  /// Loads `id -> manifest JSON` pairs (from bundled assets or tests).
  /// Returns manifest validation errors keyed by id.
  Map<String, List<String>> loadCatalog(Map<String, String> jsonById) {
    final errors = <String, List<String>>{};
    for (final entry in jsonById.entries) {
      try {
        final m = CoreManifest.fromJson(
          json.decode(entry.value) as Map<String, dynamic>,
        );
        final problems = m.validate();
        if (problems.isNotEmpty) {
          errors[entry.key] = problems;
          continue;
        }
        _catalog[m.id] = m;
      } catch (e) {
        errors[entry.key] = ['unparseable manifest: $e'];
      }
    }
    notifyListeners();
    return errors;
  }

  /// Installs a core after verifying [expectedSha256] of the artifact.
  /// Throws [StateError] on policy violation or hash mismatch.
  void install(CoreManifest m, {required String expectedSha256}) {
    if (m.blocked) {
      throw StateError('${m.name} is on hold: ${m.blockedReason}');
    }
    final pinned = m.artifacts.values;
    if (pinned.isNotEmpty && !pinned.contains(expectedSha256)) {
      throw StateError('Artifact hash not pinned in manifest for ${m.id}');
    }
    _installed[m.id] = m.version;
    _artifactSha[m.id] = expectedSha256;
    notifyListeners();
  }

  void update(CoreManifest m, {required String expectedSha256}) {
    if (!isInstalled(m.id)) {
      throw StateError('${m.id} is not installed');
    }
    install(m, expectedSha256: expectedSha256);
  }

  /// Removes a core. Returns reclaimed bytes when [artifactBytes] known.
  int remove(String id, {int artifactBytes = 0}) {
    _installed.remove(id);
    _artifactSha.remove(id);
    notifyListeners();
    return artifactBytes;
  }

  /// Cores able to open [extension] (installed only).
  List<CoreManifest> compatibleCores(String extension) {
    final ext = extension.toLowerCase().replaceFirst('.', '');
    return installedCores
        .where((m) => m.extensions.map((e) => e.toLowerCase()).contains(ext))
        .toList();
  }
}
