import 'dart:typed_data';

/// What the player needs from whatever runs a core session.
///
/// Two implementations: [EmulationWorker] runs the core in this process (a
/// Dart isolate — fast, but a native crash kills the app), and
/// `ProcessSessionBackend` runs it in a separate `ezcore_core_host` process,
/// so a crash ends only the session (P6, ADR-015). The player talks to this
/// surface and does not care which one it has.
abstract interface class CoreSessionBackend {
  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
  });

  /// Runs [count] frames (1-8); null when paused or no frame exists yet.
  /// Keys: `width`, `height`, `rgba` (Uint8List), `pcm` (Uint8List).
  Future<Map<String, dynamic>?> frame({int count = 1});

  Future<void> pause(bool value);

  Future<void> button(int id, bool pressed, {int port = 0});

  Future<Uint8List> save();

  Future<void> restore(Uint8List bytes);

  /// Each entry is `[index, enabled, code]`; returns indices the core could
  /// not take.
  Future<List<int>> applyCheats(List<List<Object>> cheats);

  Future<void> reset();

  Future<List<Map<String, String>>> coreOptions();

  Future<bool> setCoreOption(String key, String value);

  Future<void> close();
}
