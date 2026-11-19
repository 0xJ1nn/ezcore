import 'dart:io';

import 'package:flutter/material.dart';

import '../models/game_entry.dart';
import '../services/bios_check.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/symbols.dart';
import '../widgets/launch_error.dart';
import '../widgets/library_looks/look_theme.dart' show designBiosSystems;
import 'player_screen.dart';

/// The one place a game is started from, so every entry point (Resume, a
/// tile, the detail page) picks the core the same way.
///
/// The game's remembered core is used when it is still installed and opens
/// the file; otherwise the first installed core that does, which is then
/// remembered. With [resume], play continues from the automatic snapshot
/// taken when the game was last left, when one exists — whatever core the
/// game runs on.
///
/// Launch is checked before anything starts: a missing core or a missing
/// user-supplied BIOS produces an error that names the fix and routes to
/// Systems. Nothing is downloaded and no store is implied.
Future<void> launchGame(
  BuildContext context,
  AppState state,
  GameEntry game, {
  bool resume = false,

  /// Load this save right after boot (from the game page's saves).
  String? slot,

  /// Routes the "Open Systems" / "See core details" action to the shell.
  VoidCallback? onOpenSystems,
}) async {
  final compatible = state.registry.compatibleCores(game.extension);
  if (compatible.isEmpty) {
    final ext = game.extension.toLowerCase().replaceFirst('.', '');
    final available = state.registry.catalog
        .where((m) => m.extensions.any((e) => e.toLowerCase() == ext))
        .firstOrNull;
    final coreName = available?.name ?? 'required';
    final system = systemLabel(game.system);
    final route = await showLaunchError<String>(
      context,
      title: '$system isn’t installed',
      body: '${game.title} needs the $coreName core. It’s bundled with '
          'ezCORE and installs offline in a few seconds.',
      icon: Symbols.extensionOff,
      actions: const [
        LaunchErrorAction(label: 'Open Systems', value: 'systems', primary: true),
        LaunchErrorAction(label: 'Not now', value: 'cancel'),
      ],
    );
    if (route == 'systems') onOpenSystems?.call();
    return;
  }

  final current = compatible.where((m) => m.id == game.coreId);
  final effective = current.isNotEmpty ? current.first : compatible.first;
  if (effective.id != game.coreId) {
    state.setCore(game.id, effective.id);
  }

  // A user-supplied dump is checked before boot. The library badge and this
  // gate read the same design table, so a "Needs BIOS" cover can never start
  // without the dialog naming the file. Cores with a free fallback and no
  // design requirement still start normally.
  final bios = await BiosCheck().check(effective);
  if (!context.mounted) return;
  // The catalog marks most dumps optional because their cores ship a free
  // fallback. The design still blocks the PlayStation launch until the
  // reader's own dump is present, so check those files unconditionally.
  final designBios = designBiosSystems.contains(game.system);
  final missing = designBios
      ? _missingDumps(effective.biosFiles, bios.systemDir)
      : bios.missing;
  if (missing.isNotEmpty && (bios.required || designBios)) {
    // The design names the NTSC-U dump when a core accepts several regions.
    const preferred = 'scph5501.bin';
    final file = missing.contains(preferred) ? preferred : missing.first;
    final system = systemLabel(game.system);
    final route = await showLaunchError<String>(
      context,
      title: 'BIOS file needed',
      body: '${game.title} runs on the $system core, which needs $file. '
          'ezCORE never downloads BIOS files. Copy the one dumped from your '
          'own console into your games folder and it will be found '
          'automatically.',
      icon: Symbols.memory,
      actions: const [
        LaunchErrorAction(label: 'Got it', value: 'ok', primary: true),
        LaunchErrorAction(label: 'See core details', value: 'systems'),
      ],
    );
    if (route == 'systems') onOpenSystems?.call();
    return;
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

/// BIOS presence for systems the design gates on a user-supplied dump, even
/// when the bundled core also has a free fallback. Mirrors [BiosCheck]'s
/// file/directory rule without changing its production behaviour.
List<String> _missingDumps(List<String> files, String systemDir) => [
  for (final name in files)
    if (!_hasDump('$systemDir/$name')) name,
];

bool _hasDump(String path) {
  if (File(path).existsSync()) return true;
  final dir = Directory(path);
  return dir.existsSync() && dir.listSync().any((entity) => entity is File);
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
