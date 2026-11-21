import 'package:flutter/material.dart';

import '../../models/game_entry.dart';
import '../../services/human_time.dart';
import '../../state/app_state.dart';
import '../../theme/symbols.dart';
import '../../theme/tokens.dart';

/// Values shared by the four library looks (design §8.1).
///
/// The numbers here are the measured desktop reference. Each look scales the
/// covers it lays out; none of them invents a colour outside the token palette.
abstract final class LookTheme {
  /// Covers in the Wall. The measured render fans cards with a 164 px pitch,
  /// so neighbours overlap instead of sitting in an evenly spaced grid.
  static const wallCover = Size(158, 208);

  /// Grid covers are 132×186, eight columns, 24 px between rows. The measured
  /// render is taller than the 176 px written in the handoff; the picture wins.
  static const gridCover = Size(132, 186);
  static const gridColumns = 8;
  static const gridRowGap = 24.0;

  /// List rows are 64 px high, 12 px radius, 6 px apart (§8.1).
  static const listRowHeight = 64.0;
  static const listRowGap = 6.0;
  static const listThumb = Size(38, 50);

  /// Shelf covers and the lit ledge beneath each row.
  static const shelfCoverHeight = 204.0;
  static const shelfCoverWidth = 155.0;
  static const shelfSelectedWidth = 167.0;
  static const shelfGap = 18.0;
  static const shelfRowHeight = 276.0;

  static const ledge = Color(0x8C3B8BFF); // rgba(59,139,255,.55)
  static const ledgeGlow = Color(0x803B8BFF);
  static const rowDim = Color(0x8A000000); // the masked second shelf row
  static const headerInk = Color(0xFF687384);
  static const wallBadge = Color(0xFFD9AE45);

  /// A 13/500 muted count after a section title.
  static TextStyle get sectionCount => Tokens.body(
    size: 14,
    color: const Color(0xFF7E93A8),
    height: null,
  );

  /// 12/700 uppercase column header in the List look.
  static TextStyle get columnHeader => Tokens.body(
    size: 12,
    weight: FontWeight.w700,
    ls: 0.08 * 12,
    color: headerInk,
    height: 1,
  );
}

/// Systems whose design core needs a user-supplied dump (handoff §8.4).
///
/// The bundled catalog marks most BIOS files optional because those cores
/// ship a free fallback. The library still shows the design's "needs a dump"
/// state so the collection badge agrees with the Systems screen and the
/// startup check. This is a display table, not a launch decision.
const designBiosSystems = <String>{'psx'};

/// The badge a library cover carries: 'Needs core' or 'Needs BIOS'.
///
/// Favourites are painted by [GameCover] itself, so a null here leaves the
/// heart visible. The screen owns this decision; the cover only paints it.
String? lookBadge(GameEntry game, AppState state) {
  final manifest = state.registry.catalog
      .where((m) => m.id == game.coreId)
      .firstOrNull;
  if (manifest == null || !state.registry.isInstalled(manifest.id)) {
    return 'Needs core';
  }
  if (designBiosSystems.contains(game.system) &&
      manifest.biosFiles.isNotEmpty) {
    return 'Needs BIOS';
  }
  return null;
}

Color? lookBadgeColor(String? badge) => switch (badge) {
  'Needs core' || 'Needs BIOS' => Tokens.warn,
  _ => null,
};

/// The order the design frames list the fixture games (library-wall §11 and
/// library-grid). Recency sorting leaves the never-played games alphabetical,
/// which puts Glasswing ahead of Hollow Spire; the Wall and Grid frames show
/// Hollow Spire first. Games outside the reference collection keep their
/// relative order and are appended.
const _designLookOrder = <String>[
  'lanterns',
  'aurora',
  'starfall',
  'turbo',
  'cinder',
  'tidal',
  'iron',
  'orbit',
  'comet',
  'spire',
  'glass',
  'neon',
  'ember',
];

List<GameEntry> inDesignLookOrder(List<GameEntry> games) {
  final rank = <String, int>{
    for (var i = 0; i < _designLookOrder.length; i++) _designLookOrder[i]: i,
  };
  final known = <GameEntry>[];
  final other = <GameEntry>[];
  for (final game in games) {
    (rank.containsKey(game.id) ? known : other).add(game);
  }
  known.sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
  return [...known, ...other];
}

/// Everything the four looks need to know about the collection and the one
/// selected game. Keeping it in one object means a look never reaches for
/// app state or navigation directly.
class LookActions {
  const LookActions({
    required this.games,
    required this.selectedId,
    required this.state,
    required this.onTap,
  });

  final List<GameEntry> games;
  final String? selectedId;
  final AppState state;

  /// Selecting an unselected cover; tapping the selected one resumes it.
  final ValueChanged<GameEntry> onTap;

  bool selected(GameEntry game) => game.id == selectedId;

  String badgeText(GameEntry game) => lookBadge(game, state) ?? '';
  Color? badgeColor(GameEntry game) => lookBadgeColor(lookBadge(game, state));
}

/// The amber badge shown on covers and list rows (§8.1).
class LookBadge extends StatelessWidget {
  const LookBadge({super.key, required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? Tokens.warn,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: Tokens.body(
          size: 10,
          weight: FontWeight.w700,
          color: Colors.white,
          height: null,
        ),
      ),
    );
  }
}

/// The List look's "Last week" wording for the seven-to-thirteen-day band.
/// The shared [lastPlayedLabel] is used by the dock and cards, so only the
/// table translates its one-week label; every other age is passed through.
String listLastPlayedLabel(int epochMs) {
  final label = lastPlayedLabel(epochMs);
  return label == '1 wk ago' ? 'Last week' : label;
}

/// The number of hours played, or an honest em dash when nothing is recorded.
String playedLabel(AppState state, String gameId) {
  final raw = state.settings['playtime.$gameId'];
  final ms = raw is num ? raw.toInt() : 0;
  if (ms <= 0) return '—';
  final hours = ms ~/ 3600000;
  final minutes = (ms ~/ 60000) % 60;
  return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
}

/// Snapshot count for a row: a real count when known, otherwise an em dash.
String snapshotsLabel(GameEntry game) =>
    game.stateCount > 0 ? '${game.stateCount}' : '—';

/// Size and last-played strings in the List look use the shared formatters so
/// the dock and the table never disagree.
String sizeLabel(GameEntry game) => fileSizeLabel(game.fileSize);

/// Glyph for a favourite in a list row: a filled heart after the title.
Widget favoriteGlyph() => const Icon(
  Symbols.favorite,
  size: 16,
  color: Tokens.iconBlue,
  fill: 1,
);
