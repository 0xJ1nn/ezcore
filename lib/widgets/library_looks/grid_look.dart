import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'library_cover.dart';
import 'look_theme.dart';

/// Grid: every cover at a glance. Eight columns of 132×176 on desktop, three
/// columns on a phone, with the design's 24 px row rhythm (§8.1).
class GridLook extends StatelessWidget {
  const GridLook({super.key, required this.actions, this.compact = false});

  final LookActions actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final games = inDesignLookOrder(actions.games);
        final columns = compact ? 3 : LookTheme.gridColumns;
        final pad = compact ? 12.0 : 47.0;
        final cover = compact
            ? Size((c.maxWidth - pad * 2 - 12) / columns, 0)
            : LookTheme.gridCover;
        final height = compact ? cover.width * 176 / 132 : cover.height;
        final crossSpacing = compact
            ? 6.0
            : ((c.maxWidth - pad * 2) - columns * cover.width) /
                (columns - 1);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(pad, compact ? 8 : 20, pad, 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: compact ? 12 : LookTheme.gridRowGap,
            crossAxisSpacing: compact
                ? 12
                : (crossSpacing < 8 ? 8 : crossSpacing - 2),
            mainAxisExtent: height,
          ),
          itemCount: games.length,
          itemBuilder: (context, i) {
            final game = games[i];
            final badge = lookBadge(game, actions.state);
            return LookTile(
              onTap: () => actions.onTap(game),
              radius: Tokens.radiusCover,
              lift: 1.02,
              semanticLabel: game.title,
              semanticHint: actions.selected(game) ? 'Resume' : 'Show details',
              child: LibraryCover(
                gameId: game.id,
                title: libraryCoverTitle(
                  game.title,
                  coverWidth: cover.width,
                ),
                systemId: game.system,
                year: game.year,
                favorite: game.favorite,
                badgeText: badge,
                badgeColor: lookBadgeColor(badge),
                width: cover.width + (actions.selected(game) ? 10 : 0),
                height: height,
                radius: Tokens.radiusCover,
                selected: actions.selected(game),
              ),
            );
          },
        );
      },
    );
  }
}
