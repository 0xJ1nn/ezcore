/// Core-option precedence layers, ordered from lowest to highest.
///
/// The runtime (see `package:ezcore/runtime/ezcore_runtime.dart`) exposes
/// individual core options read from the loaded libretro core. This enum
/// orders the host-supplied layers that those values are merged across.
enum CoreOptionLayer {
  /// Global defaults (always present, lowest precedence).
  global,

  /// Per-system defaults (e.g. the platform the core belongs to).
  system,

  /// Per-core defaults (the current core's recommended values).
  core,

  /// Per-game overrides (the active game's choices, highest precedence).
  game,
}

/// The winning value for a single core option, plus its source layer.
class ResolvedCoreOption {
  const ResolvedCoreOption({required this.value, required this.layer});

  /// The value chosen for this option.
  final String value;

  /// Which layer supplied the winning value.
  final CoreOptionLayer layer;

  /// Lowercase name of the winning layer (`global`, `system`, `core`, `game`).
  String get layerName => layer.name;
}

/// A pure-logic resolver for core option values across four precedence
/// layers: `global < system < core < game`.
///
/// No I/O, no UI: configure layers through the per-layer setters, then call
/// [resolve] (or [resolveAll]) to obtain each option's winning value and the
/// layer it originated from. The FFI bindings in
/// `package:ezcore/runtime/ezcore_runtime.dart` are expected to feed core
/// option *keys* and their current values into [setCore]; the worker-protocol
/// wiring that performs that feeding (issue #42) is out of scope here.
class CoreOptionsResolver {
  final Map<String, String> _global = {};
  final Map<String, String> _system = {};
  final Map<String, String> _core = {};
  final Map<String, String> _game = {};

  /// The global default layer (lowest precedence).
  Map<String, String> get global => Map.unmodifiable(_global);

  /// The per-system default layer.
  Map<String, String> get system => Map.unmodifiable(_system);

  /// The per-core default layer.
  Map<String, String> get core => Map.unmodifiable(_core);

  /// The per-game override layer (highest precedence).
  Map<String, String> get game => Map.unmodifiable(_game);

  /// Records a value on the global layer.
  void setGlobal(String key, String value) {
    _global[key] = value;
  }

  /// Records a value on the per-system layer.
  void setSystem(String key, String value) {
    _system[key] = value;
  }

  /// Records a value on the per-core layer.
  void setCore(String key, String value) {
    _core[key] = value;
  }

  /// Records a value on the per-game layer.
  void setGame(String key, String value) {
    _game[key] = value;
  }

  /// Removes every entry from [layer].
  void clearLayer(CoreOptionLayer layer) {
    switch (layer) {
      case CoreOptionLayer.global:
        _global.clear();
      case CoreOptionLayer.system:
        _system.clear();
      case CoreOptionLayer.core:
        _core.clear();
      case CoreOptionLayer.game:
        _game.clear();
    }
  }

  /// Resolves each key in [optionKeys] to its highest-precedence value.
  ///
  /// Layers are applied from lowest to highest precedence (global -> system
  /// -> core -> game), so a deeper layer always wins — even when its value is
  /// identical to a shallower layer's. A key absent from every layer is
  /// omitted from the result.
  Map<String, ResolvedCoreOption> resolve(Iterable<String> optionKeys) {
    final result = <String, ResolvedCoreOption>{};
    final layers = [
      (CoreOptionLayer.global, _global),
      (CoreOptionLayer.system, _system),
      (CoreOptionLayer.core, _core),
      (CoreOptionLayer.game, _game),
    ];
    for (final (layer, map) in layers) {
      for (final key in optionKeys) {
        final value = map[key];
        if (value != null) {
          result[key] = ResolvedCoreOption(value: value, layer: layer);
        }
      }
    }
    return result;
  }

  /// Resolves every key known across all four layers.
  Map<String, ResolvedCoreOption> resolveAll() {
    return resolve({
      ..._global.keys,
      ..._system.keys,
      ..._core.keys,
      ..._game.keys,
    });
  }
}
