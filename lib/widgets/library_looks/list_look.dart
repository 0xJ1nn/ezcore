import 'package:flutter/material.dart';

import '../../models/game_entry.dart';
import '../../services/system_labels.dart';
import '../../state/app_state.dart' show contentPresentFor;
import '../../theme/tokens.dart';
import 'library_cover.dart';
import 'look_theme.dart';

/// List: titles and details in columns. The header and the 64 px rows use the
/// same column grid so every fact lines up (§8.1).
class ListLook extends StatelessWidget {
  const ListLook({super.key, required this.actions, this.compact = false});

  final LookActions actions;
  final bool compact;

  static const _columns = [56.0, -1.0, 220.0, 150.0, 110.0, 110.0, 100.0];
  static const _gap = 16.0;
  static const _pad = 18.0;

  @override
  Widget build(BuildContext context) {
    if (compact) return _PhoneList(actions: actions);
    // The measured list puts its column header at y=232, 18 px above where
    // the shared content band would otherwise start it.
    return Transform.translate(
      offset: const Offset(0, -18),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: _RowLayout(
              child: const [
                SizedBox.shrink(),
                _HeaderCell('TITLE'),
                _HeaderCell('SYSTEM'),
                _HeaderCell('LAST PLAYED'),
                _HeaderCell('PLAYED'),
                _HeaderCell('SNAPSHOTS'),
                _HeaderCell('SIZE'),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(44, 6, 44, 24),
            itemCount: actions.games.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: LookTheme.listRowGap),
            itemBuilder: (context, i) => _ListRow(
              game: actions.games[i],
              actions: actions,
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: LookTheme.columnHeader);
}

/// The shared column geometry: a fixed thumb cell, a flexible title cell and
/// five fixed fact cells, all with the design's 16 px gap.
class _RowLayout extends StatelessWidget {
  const _RowLayout({required this.child});

  final List<Widget> child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: ListLook._pad),
        for (var i = 0; i < child.length; i++) ...[
          if (i == 1)
            Expanded(child: child[i])
          else
            SizedBox(width: ListLook._columns[i], child: child[i]),
          if (i < child.length - 1) const SizedBox(width: ListLook._gap),
        ],
        const SizedBox(width: ListLook._pad),
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({required this.game, required this.actions});

  final GameEntry game;
  final LookActions actions;

  @override
  Widget build(BuildContext context) {
    final selected = actions.selected(game);
    final badge = lookBadge(game, actions.state);
    return LookTile(
      onTap: () => actions.onTap(game),
      radius: 12,
      lift: 1,
      semanticLabel: game.title,
      semanticHint: selected ? 'Resume' : 'Show details',
      child: Container(
        height: LookTheme.listRowHeight,
        decoration: BoxDecoration(
          color: selected ? const Color(0x1ADDE6F4) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(color: const Color(0x99007BFF))
              : null,
          boxShadow: selected
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x10DDE6F4),
                    offset: Offset(0, 1),
                  ),
                ],
        ),
        child: _RowLayout(
          child: [
            Center(
              child: LibraryCover(
                gameId: game.id,
                title: libraryCoverTitle(game.title, coverWidth: 38),
                systemId: game.system,
                width: LookTheme.listThumb.width,
                height: LookTheme.listThumb.height,
                radius: 4,
                contentPresent: contentPresentFor(
                  game,
                  actions.state.romFolders,
                ),
              ),
            ),
            Row(
              children: [
                Flexible(
                  child: Text(
                    game.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: 16,
                      weight: FontWeight.w700,
                      color: selected ? Tokens.text : Tokens.muted,
                      height: 1,
                    ),
                  ),
                ),
                if (game.favorite) ...[
                  const SizedBox(width: 10),
                  favoriteGlyph(),
                ],
                if (badge != null) ...[
                  const SizedBox(width: 10),
                  LookBadge(text: badge, color: lookBadgeColor(badge)),
                ],
              ],
            ),
            _Fact(systemLabel(game.system)),
            _Fact(listLastPlayedLabel(game.lastPlayedMs)),
            _Fact(playedLabel(actions.state, game.id)),
            _Fact(snapshotsLabel(game)),
            _Fact(sizeLabel(game)),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: Tokens.body(size: 14, color: Tokens.muted, height: 1),
  );
}

/// Phone List: the same covers and titles, reduced to the two lines that fit
/// a thumb-width row, with recorded playtime on the right (Devices 4b).
class _PhoneList extends StatelessWidget {
  const _PhoneList({required this.actions});
  final LookActions actions;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: actions.games.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, i) {
        final game = actions.games[i];
        final selected = actions.selected(game);
        return LookTile(
          onTap: () => actions.onTap(game),
          radius: 10,
          lift: 1,
          semanticLabel: game.title,
          semanticHint: selected ? 'Resume' : 'Show details',
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0x14007BFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: selected
                  ? Border.all(color: const Color(0x80007BFF))
                  : null,
            ),
            child: Row(
              children: [
                LibraryCover(
                  gameId: game.id,
                  title: libraryCoverTitle(game.title, coverWidth: 38),
                  systemId: game.system,
                  width: 36,
                  height: 48,
                  radius: 4,
                  contentPresent: contentPresentFor(
                    game,
                    actions.state.romFolders,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        game.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: 15,
                          weight: FontWeight.w700,
                          color: selected ? Tokens.text : Tokens.muted,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        systemLabel(game.system),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Tokens.body(
                          size: 12,
                          color: Tokens.muted,
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  playedLabel(actions.state, game.id),
                  style: Tokens.body(
                    size: 12,
                    color: Tokens.muted,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
