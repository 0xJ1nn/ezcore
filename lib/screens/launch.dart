import 'package:flutter/material.dart';

import '../models/game_entry.dart';
import '../state/app_state.dart';
import '../widgets/orbit_widgets.dart';
import 'player_screen.dart';

/// The one place a game is started from, so every entry point (Resume, a
/// tile, the detail page) picks the core the same way.
///
/// The game's remembered core is used when it is still installed and opens
/// the file; otherwise the first installed core that does, which is then
/// remembered. With [resume], play continues from the automatic snapshot
/// taken when the game was last left, when one exists — whatever core the
/// game runs on.
Future<void> launchGame(
  BuildContext context,
  AppState state,
  GameEntry game, {
  bool resume = false,

  /// Load this save right after boot (from the game page's saves).
  String? slot,
}) async {
  final compatible = state.registry.compatibleCores(game.extension);
  if (compatible.isEmpty) {
    orbitToast(context, 'No installed core opens this file yet');
    return;
  }
  final current = compatible.where((m) => m.id == game.coreId);
  final effective = current.isNotEmpty ? current.first : compatible.first;
  if (effective.id != game.coreId) {
    state.setCore(game.id, effective.id);
  }
  if (resume && slot == null) {
    try {
      final slots = await state.saves.list(game.id);
      if (slots.any((s) => s.id == autoSlot)) slot = autoSlot;
    } catch (_) {
      // No readable snapshot: start fresh rather than fail to launch.
    }
  }
  state.recordPlay(game.id);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          PlayerScreen(gameId: game.id, state: state, initialSlot: slot),
    ),
  );
}

/// The snapshot slot the player writes when a game is left or backgrounded.
const autoSlot = 'auto';

/// The game played most recently, on any core, or null if none has been.
GameEntry? lastPlayed(List<GameEntry> games) {
  GameEntry? best;
  for (final g in games) {
    if (g.lastPlayedMs <= 0) continue;
    if (best == null || g.lastPlayedMs > best.lastPlayedMs) best = g;
  }
  return best;
}
