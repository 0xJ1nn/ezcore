import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/game_entry.dart';
import '../../state/app_state.dart' show contentPresentFor;
import 'library_cover.dart';
import 'look_theme.dart';

/// Wall: poster-sized covers fanned along a curved wall, with the camera
/// turned toward the selected column (§8.1). Cards overlap their neighbour by
/// about 10 px and a later card is drawn on top, so the row reads as a wall
/// rather than an evenly spaced grid.
class WallLook extends StatelessWidget {
  const WallLook({super.key, required this.actions, this.compact = false});

  final LookActions actions;
  final bool compact;

  static const _columns = 6;
  static const _step = 164.0;
  static const _rowStep = 237.0;
  static const _left = 592.0; // x691 in the 1440 px reference, inside the rail

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final size = compact
            ? const Size(116, 156)
            : LookTheme.wallCover;
        final step = compact ? 96.0 : _step;
        final left = compact ? 12.0 : _left;
        final games = inDesignLookOrder(actions.games);
        final selectedIndex = games.indexWhere(actions.selected);
        final selected = selectedIndex < 0 ? 0 : selectedIndex;
        final focusedCol = compact ? 0 : selected % _columns;
        final focusedRow = compact ? 0 : selected ~/ _columns;
        final children = <Widget>[];
        for (var i = 0; i < games.length; i++) {
          final row = compact ? 0 : i ~/ _columns;
          final col = compact ? i : i % _columns;
          children.add(
            _WallCard(
              game: games[i],
              actions: actions,
              size: size,
              left: left + (col - focusedCol) * step,
              top: compact
                  ? (i ~/ 3) * 158.0
                  : -6.0 + (row - focusedRow) * _rowStep,
              dimmed: row != focusedRow,
            ),
          );
        }
        // The fan overlaps left to right, but the selected card keeps its
        // full outline, so it is painted above its neighbours (wall §11).
        if (selected >= 0 && selected < children.length) {
          children.add(children.removeAt(selected));
        }
        return ClipRect(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: compact
                  ? c.maxWidth
                  : math.max(c.maxWidth, left + _columns * step),
              height: compact ? c.maxHeight : _rowStep * 2 + size.height,
              child: Stack(children: children),
            ),
          ),
        );
      },
    );
  }
}

class _WallCard extends StatelessWidget {
  const _WallCard({
    required this.game,
    required this.actions,
    required this.size,
    required this.left,
    required this.top,
    required this.dimmed,
  });

  final GameEntry game;
  final LookActions actions;
  final Size size;
  final double left;
  final double top;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final selected = actions.selected(game);
    final badge = lookBadge(game, actions.state);
    // The design's wall carries a constant, subtle -3° yaw. A per-column
    // perspective turn made the cards read as separate trapezoids; a shared
    // yaw keeps the overlap reading as one gently curved surface.
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.001)
      ..rotateY(-3 * math.pi / 180);
    final scale = selected ? 1.05 : 1.0;
    return Positioned(
      left: left,
      top: top,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Transform(
          transform: matrix,
          alignment: Alignment.center,
          child: LookTile(
            onTap: () => actions.onTap(game),
            radius: 7,
            lift: 1,
            semanticLabel: game.title,
            semanticHint: selected ? 'Resume' : 'Show details',
            child: Transform.scale(
              scale: scale,
              child: LibraryCover(
                gameId: game.id,
                title: libraryCoverTitle(game.title, coverWidth: size.width),
                systemId: game.system,
                year: game.year,
                favorite: game.favorite,
                badgeText: badge,
                badgeColor: lookBadgeColor(badge),
                width: size.width,
                height: size.height,
                radius: 7,
                selected: selected,
                contentPresent: contentPresentFor(
                  game,
                  actions.state.romFolders,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
