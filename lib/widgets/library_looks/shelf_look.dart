import 'package:flutter/material.dart';

import '../../models/game_entry.dart';
import '../../theme/tokens.dart';
import 'library_cover.dart';
import 'look_theme.dart';

/// The system families on a handheld shelf (§8.1). Everything else sits on the
/// home-console shelf. The partition is stable: games keep their collection
/// order inside each row.
const handheldSystems = <String>{
  'gb',
  'gbc',
  'gba',
  'nds',
  'psp',
  'gg',
  '3ds',
  'switch',
};

({List<GameEntry> handhelds, List<GameEntry> consoles}) splitShelfGames(
  List<GameEntry> games,
) {
  final handhelds = <GameEntry>[];
  final consoles = <GameEntry>[];
  for (final game in games) {
    (handheldSystems.contains(game.system) ? handhelds : consoles).add(game);
  }
  return (handhelds: handhelds, consoles: consoles);
}

/// Shelf: rows of tall covers on a lit ledge, with the row below the focus
/// dimmed and masked so the shelf reads as a space with depth (§8.1).
class ShelfLook extends StatelessWidget {
  const ShelfLook({super.key, required this.actions, this.compact = false});

  final LookActions actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final groups = splitShelfGames(actions.games);
    final rows = <(String, List<GameEntry>)>[
      ('Handhelds', groups.handhelds),
      ('Home consoles', groups.consoles),
    ]..removeWhere((row) => row.$2.isEmpty);
    if (rows.isEmpty) return const SizedBox.shrink();

    final selectedRow = rows.indexWhere(
      (row) => row.$2.any(actions.selected),
    );
    final focus = selectedRow < 0 ? 0 : selectedRow;

    return ClipRect(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 20, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++)
              _ShelfRow(
                title: rows[i].$1,
                games: rows[i].$2,
                actions: actions,
                dimmed: i > focus,
                compact: compact,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.title,
    required this.games,
    required this.actions,
    required this.dimmed,
    required this.compact,
  });

  final String title;
  final List<GameEntry> games;
  final LookActions actions;
  final bool dimmed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 150.0 : LookTheme.shelfCoverHeight;
    final coverWidth = compact ? 104.0 : LookTheme.shelfCoverWidth;
    final selectedWidth = compact ? 116.0 : LookTheme.shelfSelectedWidth;
    final gap = compact ? 12.0 : LookTheme.shelfGap;

    Widget row = SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 28),
        itemCount: games.length,
        separatorBuilder: (_, _) => SizedBox(width: gap),
        itemBuilder: (context, i) {
          final game = games[i];
          final selected = actions.selected(game);
          final badge = lookBadge(game, actions.state);
          return LookTile(
            onTap: () => actions.onTap(game),
            radius: 8,
            lift: 1.02,
            semanticLabel: game.title,
            semanticHint: selected ? 'Resume' : 'Show details',
            child: LibraryCover(
              gameId: game.id,
              title: libraryCoverTitle(game.title),
              systemId: game.system,
              year: game.year,
              favorite: game.favorite,
              badgeText: badge,
              badgeColor: lookBadgeColor(badge),
              width: selected ? selectedWidth : coverWidth,
              height: height,
              radius: 8,
              selected: selected,
            ),
          );
        },
      ),
    );

    if (dimmed) {
      row = Opacity(
        opacity: 0.5,
        child: ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.4, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: row,
        ),
      );
    }

    return SizedBox(
      height: compact
          ? height + 58
          : LookTheme.shelfRowHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(compact ? 20 : 25, 8, 44, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  title,
                  style: Tokens.display(
                    size: compact ? 17 : 19,
                    weight: FontWeight.w600,
                    ls: -0.01 * 19,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${games.length} ${games.length == 1 ? 'game' : 'games'}',
                  style: LookTheme.sectionCount,
                ),
              ],
            ),
          ),
          Expanded(child: row),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 47),
            child: Container(
              height: 1,
              decoration: const BoxDecoration(
                color: LookTheme.ledge,
                boxShadow: [
                  BoxShadow(color: LookTheme.ledgeGlow, blurRadius: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }
}
