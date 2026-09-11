import 'package:flutter/material.dart';

import '../data/mock_library.dart';
import '../models/game_entry.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import 'game_detail_screen.dart';
import 'import_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.state});
  final AppState state;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String query = '';
  String system = 'all';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final games = _filtered(widget.state.games);
        final systems = <String>{for (final g in widget.state.games) g.system};
        return Padding(
          padding: const EdgeInsets.all(Tokens.pad),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SearchBar(
                      hintText: 'Search games',
                      onChanged: (v) => setState(
                        () => query = v.toLowerCase(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ImportScreen(state: widget.state),
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Import'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('All'),
                      selected: system == 'all',
                      onSelected: (_) => setState(() => system = 'all'),
                    ),
                    for (final s in systems.toList()..sort())
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(systemLabels[s] ?? s),
                          selected: system == s,
                          onSelected: (_) => setState(() => system = s),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (games.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No games yet.'),
                        const SizedBox(height: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  ImportScreen(state: widget.state),
                            ),
                          ),
                          child: const Text('Import a folder'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 0.78,
                    ),
                    itemCount: games.length,
                    itemBuilder: (context, i) =>
                        _Tile(game: games[i], state: widget.state),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  List<GameEntry> _filtered(List<GameEntry> games) => games.where((g) {
        if (system != 'all' && g.system != system) return false;
        if (query.isNotEmpty &&
            !g.title.toLowerCase().contains(query)) {
          return false;
        }
        return true;
      }).toList();
}

class _Tile extends StatelessWidget {
  const _Tile({required this.game, required this.state});
  final GameEntry game;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => GameDetailScreen(gameId: game.id, state: state),
          ),
        ),
        onLongPress: () => _menu(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Tokens.inkLine.withValues(alpha: 0.5),
                alignment: Alignment.center,
                child: Text(
                  game.title.characters.first.toUpperCase(),
                  style: const TextStyle(fontSize: 40, color: Tokens.muted),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          game.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (game.favorite)
                        const Icon(Icons.star,
                            size: 14, color: Tokens.coin),
                    ],
                  ),
                  Text(
                    systemLabels[game.system] ?? game.system,
                    style:
                        const TextStyle(fontSize: 11, color: Tokens.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _menu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                game.favorite ? Icons.star : Icons.star_outline,
              ),
              title: Text(
                game.favorite ? 'Unfavorite' : 'Favorite',
              ),
              onTap: () {
                state.toggleFavorite(game.id);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from library'),
              onTap: () {
                state.removeGame(game.id);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
