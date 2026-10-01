import 'dart:convert';

import '../state/app_state.dart';
import 'builtin_layouts.dart';
import 'control_layout.dart';

/// The user's own versions of on-screen layouts, saved in settings under
/// [customLayoutsKey] as `{layoutId: layout JSON}`. A saved layout replaces
/// the built-in one with the same id; resetting deletes it, so the built-in
/// (which may improve in a later version) comes back.
///
/// Stored layouts are re-validated on every load with the same strict parser
/// a package layout goes through. One that no longer validates is ignored —
/// a bad preference must never cost the player their controls.
const customLayoutsKey = 'controlLayouts';

class LayoutStore {
  LayoutStore(this.state);
  final AppState state;

  // id -> (the JSON it was parsed from, the parsed layout). Returning the
  // same instance for the same JSON matters: the player rebuilds every
  // frame, and a "new" layout would make the touch layer release controls.
  final Map<String, (String, ControlLayout?)> _cache = {};

  /// The default for [system] in this orientation: the layout the game's
  /// core package ships, if it ships one, otherwise the built-in.
  ControlLayout defaultFor(
    String system, {
    required bool portrait,
    String? coreId,
  }) =>
      (coreId == null
          ? null
          : state.packageLayouts.layoutFor(coreId, system, portrait: portrait)) ??
      builtinLayout(system, portrait: portrait);

  /// The layout to use: the user's own version when one is saved and valid,
  /// otherwise [defaultFor] — the core's layout, then the built-in.
  ControlLayout resolve(String system, {required bool portrait, String? coreId}) {
    final base = defaultFor(system, portrait: portrait, coreId: coreId);
    return custom(base.id) ?? base;
  }

  /// The user's saved version of layout [id], or null.
  ControlLayout? custom(String id) {
    final all = state.settings[customLayoutsKey];
    if (all is! Map) return null;
    final raw = all[id];
    if (raw is! Map) return null;
    final text = jsonEncode(raw);
    final hit = _cache[id];
    if (hit != null && hit.$1 == text) return hit.$2;
    final parsed = ControlLayout.parse(raw).layout;
    // The id inside must match the slot it is saved in.
    final layout = parsed?.id == id ? parsed : null;
    _cache[id] = (text, layout);
    return layout;
  }

  bool isCustomised(String id) => custom(id) != null;

  Future<void> save(ControlLayout layout) async {
    final check = ControlLayout.parse(layout.toJson());
    if (check.layout == null) {
      throw ArgumentError('layout does not validate: ${check.errors}');
    }
    final all = _copyAll();
    all[layout.id] = layout.toJson();
    await state.setSetting(customLayoutsKey, all);
  }

  Future<void> reset(String id) async {
    final all = _copyAll()..remove(id);
    _cache.remove(id);
    await state.setSetting(customLayoutsKey, all);
  }

  Map<String, dynamic> _copyAll() {
    final raw = state.settings[customLayoutsKey];
    return {
      if (raw is Map)
        for (final e in raw.entries)
          if (e.key is String && e.value is Map) e.key as String: e.value,
    };
  }
}
