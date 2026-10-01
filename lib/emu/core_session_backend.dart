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

    /// Option values applied after the core loads and before the game does.
    Map<String, String> coreOptions = const {},
  });

  /// Runs [count] frames (1-8); null when paused or no frame exists yet.
  /// Keys: `width`, `height`, `rgba` (Uint8List), `pcm` (Uint8List).
  Future<Map<String, dynamic>?> frame({int count = 1});

  Future<void> pause(bool value);

  Future<void> button(int id, bool pressed, {int port = 0});

  /// Analog stick axis: [stick] 0 left / 1 right, [axis] 0 x / 1 y.
  Future<void> analog(int port, int stick, int axis, int value);

  /// Relative mouse motion (delivered to the core once per frame).
  Future<void> mouseMove(int dx, int dy);

  /// A mouse button (RETRO_DEVICE_ID_MOUSE_*).
  Future<void> mouseButton(int id, bool pressed);

  /// A key (RETROK_*), with the typed character and RETROKMOD_* modifiers.
  Future<void> key(
    int keycode,
    bool pressed, {
    int character = 0,
    int modifiers = 0,
  });

  /// The pointer/touchscreen across the whole output, -32767..32767.
  Future<void> pointer(int x, int y, bool pressed);

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
