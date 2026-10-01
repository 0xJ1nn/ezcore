import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'game_detail_screen.dart';
import 'import_screen.dart';
import 'launch.dart';

/// Library, the home screen (layout option A, chosen 2026-10-01).
///
/// Top to bottom: search and Add games; Resume — one tap back into the game
/// played last, on whatever core it runs; Continue playing; filters; every
/// game. One layout that reflows from a phone to a desktop rather than a
/// separate design per size.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.state, this.onOpenCores});

  final AppState state;

  /// Opens the Cores destination (from the empty state).
  final VoidCallback? onOpenCores;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Sort { recent, title }

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'library search');
  String _filter = 'all'; // 'all' | 'favorites' | a system id
  _Sort _sort = _Sort.recent;

  AppState get state => widget.state;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _openImport() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ImportScreen(state: state)));

  void _openDetail(GameEntry g) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => GameDetailScreen(gameId: g.id, state: state),
    ),
  );

  List<GameEntry> _visible() {
    final q = _search.text.trim().toLowerCase();
    final out = state.games.where((g) {
      if (_filter == 'favorites' && !g.favorite) return false;
      if (_filter != 'all' && _filter != 'favorites' && g.system != _filter) {
        return false;
      }
      if (q.isEmpty) return true;
      return g.title.toLowerCase().contains(q) ||
          systemLabel(g.system).toLowerCase().contains(q);
    }).toList();
    out.sort(
      _sort == _Sort.title
          ? (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())
          : (a, b) {
              final byPlay = b.lastPlayedMs.compareTo(a.lastPlayedMs);
              return byPlay != 0
                  ? byPlay
                  : a.title.toLowerCase().compareTo(b.title.toLowerCase());
            },
    );
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.slash): () =>
            _searchFocus.requestFocus(),
      },
      child: ListenableBuilder(
        listenable: state,
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) => _body(c.maxWidth, c.maxHeight),
        ),
      ),
    );
  }

  Widget _body(double width, double height) {
    final compact = width < 600;
    // Short landscape phones: keep Resume to a slim strip so the library
    // is still visible below it.
    final short = height < 480;
    final pad = compact ? 16.0 : (width >= 1180 ? 40.0 : 24.0);
    final games = state.games;
    final last = lastPlayed(games);
    final recent = [
      for (final g in games)
        if (g.lastPlayedMs > 0 && g.id != last?.id) g,
    ]..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    final visible = _visible();

    return CustomScrollView(
      slivers: [
        // Nothing to search yet: the empty state carries the one action.
        if (games.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              pad,
              compact || short ? 16 : 28,
              pad,
              0,
            ),
            sliver: SliverToBoxAdapter(child: _header(compact)),
          ),
        if (games.isEmpty)
          SliverToBoxAdapter(child: _empty())
        else ...[
          if (last != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
              sliver: SliverToBoxAdapter(
                child: _ResumeCard(
                  game: last,
                  state: state,
                  compact: compact,
                  short: short,
                  onDetails: () => _openDetail(last),
                ),
              ),
            ),
          if (recent.isNotEmpty) ...[
            _sectionTitle('Continue playing', pad),
            SliverToBoxAdapter(
              child: SizedBox(
                height: compact ? 200 : 236,
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  scrollDirection: Axis.horizontal,
                  itemCount: recent.length.clamp(0, 12),
                  separatorBuilder: (_, _) => const SizedBox(width: 14),
                  itemBuilder: (context, i) => SizedBox(
                    width: compact ? 116 : 140,
                    child: _Tile(
                      game: recent[i],
                      footnote: lastPlayedLabel(recent[i].lastPlayedMs),
                      onTap: () =>
                          launchGame(context, state, recent[i], resume: true),
                      semanticsHint: 'Resume',
                    ),
                  ),
                ),
              ),
            ),
          ],
          _sectionTitle('All games', pad, trailing: _sortButton()),
          SliverToBoxAdapter(child: _filters(pad)),
          if (visible.isEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 32, pad, 48),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'No games match. Try another filter or search.',
                  style: Tokens.body(size: 13, color: Tokens.muted),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: compact ? 130 : 176,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: compact ? 12 : 18,
                  childAspectRatio: 0.58,
                ),
                itemCount: visible.length,
                itemBuilder: (context, i) => _Tile(
                  game: visible[i],
                  footnote: shortSystemLabel(visible[i].system),
                  onTap: () => _openDetail(visible[i]),
                  semanticsHint: 'Open details',
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _header(bool compact) {
    final search = OrbitSearch(
      controller: _search,
      onChanged: (_) => setState(() {}),
      hint: 'Search your games',
      shortcutLabel: compact ? null : 'Ctrl K',
    );
    return Row(
      children: [
        Expanded(
          child: Focus(focusNode: _searchFocus, child: search),
        ),
        const SizedBox(width: 12),
        compact
            ? OrbitIconButton(
                icon: Icons.add,
                tooltip: 'Add games',
                onPressed: _openImport,
              )
            : OrbitPrimary(
                label: 'Add games',
                icon: Icons.add,
                minHeight: 44,
                onPressed: _openImport,
              ),
      ],
    );
  }

  Widget _sectionTitle(String text, double pad, {Widget? trailing}) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, 28, pad, 12),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: Tokens.display(size: 19, weight: FontWeight.w600),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );

  Widget _sortButton() => TextButton.icon(
    onPressed: () => setState(
      () => _sort = _sort == _Sort.recent ? _Sort.title : _Sort.recent,
    ),
    icon: const Icon(Icons.swap_vert, size: 16, color: Tokens.muted),
    label: Text(
      _sort == _Sort.recent ? 'Recently played' : 'A–Z',
      style: Tokens.body(size: 12, color: Tokens.muted),
    ),
  );

  Widget _filters(double pad) {
    final counts = <String, int>{};
    for (final g in state.games) {
      counts[g.system] = (counts[g.system] ?? 0) + 1;
    }
    final systems = counts.keys.toList()
      ..sort((a, b) => systemLabel(a).compareTo(systemLabel(b)));
    final favorites = state.games.where((g) => g.favorite).length;
    Widget chip(String id, String label) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: OrbitChip(
        label: label,
        active: _filter == id,
        onTap: () => setState(() => _filter = id),
      ),
    );
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        children: [
          chip('all', 'All · ${state.games.length}'),
          if (favorites > 0) chip('favorites', 'Favorites · $favorites'),
          for (final s in systems) chip(s, systemLabel(s)),
        ],
      ),
    );
  }

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videogame_asset_outlined,
              size: 44,
              color: Tokens.muted,
            ),
            const SizedBox(height: 16),
            Text(
              'Add your first game',
              style: Tokens.display(size: 22, weight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'ezCORE plays the game files you own. Pick a file or a folder '
              'and it finds the right core for each game.',
              textAlign: TextAlign.center,
              style: Tokens.body(size: 13, color: Tokens.muted, height: 1.6),
            ),
            const SizedBox(height: 20),
            OrbitPrimary(
              label: 'Add games',
              icon: Icons.add,
              onPressed: _openImport,
            ),
            if (widget.onOpenCores != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onOpenCores,
                child: Text(
                  'See installed cores',
                  style: Tokens.body(size: 13, color: Tokens.systemLabelFg),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// One tap back into the game played last — on any core.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.game,
    required this.state,
    required this.compact,
    required this.short,
    required this.onDetails,
  });

  final GameEntry game;
  final AppState state;
  final bool compact;

  /// Little vertical room: smaller cover and title, same actions.
  final bool short;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final cover = GameCover(
      gameId: game.id,
      title: game.title,
      system: shortSystemLabel(game.system),
      width: compact || short ? 60 : 112,
      height: compact || short ? 80 : 150,
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'RESUME',
          style: Tokens.body(
            size: 11,
            weight: FontWeight.w700,
            ls: 1.2,
            color: Tokens.systemLabelFg,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          game.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Tokens.display(
            size: compact || short ? 20 : 28,
            weight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        FutureBuilder(
          future: state.saves.list(game.id),
          builder: (context, snap) {
            final hasAuto = snap.data?.any((s) => s.id == autoSlot) ?? false;
            return Text(
              '${systemLabel(game.system)} · ${lastPlayedLabel(game.lastPlayedMs)}'
              '${hasAuto ? ' · picks up where you left off' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Tokens.body(size: 13, color: Tokens.muted),
            );
          },
        ),
      ],
    );
    final resume = OrbitPrimary(
      label: 'Resume',
      expanded: compact,
      minHeight: compact ? 48 : 52,
      onPressed: () => launchGame(context, state, game, resume: true),
    );
    final details = OrbitSecondary(label: 'Details', onPressed: onDetails);

    return Container(
      padding: EdgeInsets.all(compact || short ? 14 : 20),
      decoration: BoxDecoration(
        color: Tokens.dockTop,
        borderRadius: BorderRadius.circular(Tokens.dockPanelRadius),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    cover,
                    const SizedBox(width: 14),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 14),
                resume,
              ],
            )
          : Row(
              children: [
                cover,
                const SizedBox(width: 20),
                Expanded(child: info),
                const SizedBox(width: 16),
                details,
                const SizedBox(width: 12),
                resume,
              ],
            ),
    );
  }
}

/// A game in a row or the grid: cover, title, one honest fact. Focusable,
/// so a keyboard or controller can move between games.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.game,
    required this.footnote,
    required this.onTap,
    required this.semanticsHint,
  });

  final GameEntry game;
  final String footnote;
  final VoidCallback onTap;
  final String semanticsHint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: game.title,
      hint: semanticsHint,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusCover + 4),
        focusColor: Tokens.systemLabelBg,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GameCover(
                  gameId: game.id,
                  title: game.title,
                  system: shortSystemLabel(game.system),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                game.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.body(size: 13, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                footnote,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.body(size: 11, color: Tokens.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
