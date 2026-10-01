import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/collection_view.dart';
import '../widgets/cover_flow.dart';
import '../widgets/focus_glow.dart';
import '../widgets/orbit_widgets.dart';
import 'game_detail_screen.dart';
import 'import_screen.dart';
import 'launch.dart';

/// Library, the home screen (layout option A, chosen 2026-10-01).
///
/// Three ways to see the same games, switched top right and remembered:
///  - 3D: the Orbit shelf. The focused game's art fills the background and
///    one bar carries its action — Resume if it has been played, else Play.
///    The shelf opens on the game played last, so Resume needs no card of
///    its own here.
///  - Grid and List: Resume (one tap back into the game played last, on
///    whatever core it runs), Continue playing, then every game.
/// Search, Add games, filters and sort sit in the same place in every view.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.state,
    this.onOpenCores,
    this.filterRequests,
  });

  final AppState state;

  /// Other screens ask for a filter here (Cores → Show games sends a
  /// system id); the library applies it when it changes.
  final ValueNotifier<String?>? filterRequests;

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
  int _flowIndex = 0;

  AppState get state => widget.state;

  CollectionView get _view => CollectionView.fromSetting(
    state.settings[libraryViewKey],
    fallback: CollectionView.flow,
  );

  void _setView(CollectionView v) => state.setSetting(libraryViewKey, v.value);

  @override
  void initState() {
    super.initState();
    widget.filterRequests?.addListener(_applyRequest);
  }

  void _applyRequest() {
    final f = widget.filterRequests?.value;
    if (f != null && mounted) {
      setState(() {
        _filter = f;
        _flowIndex = 0;
        _search.clear();
      });
    }
  }

  @override
  void dispose() {
    widget.filterRequests?.removeListener(_applyRequest);
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
    if (games.isEmpty) {
      return CustomScrollView(slivers: [SliverToBoxAdapter(child: _empty())]);
    }
    final visible = _visible();
    if (_view == CollectionView.flow) {
      return _flowBody(visible, compact, short, pad);
    }
    final last = lastPlayed(games);
    final recent = [
      for (final g in games)
        if (g.lastPlayedMs > 0 && g.id != last?.id) g,
    ]..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, compact || short ? 16 : 28, pad, 0),
          sliver: SliverToBoxAdapter(child: _header(compact)),
        ),
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
        _sectionTitle('All games', pad),
        SliverToBoxAdapter(child: _filters(pad)),
        if (visible.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 32, pad, 48),
            sliver: SliverToBoxAdapter(child: _noMatch()),
          )
        else if (_view == CollectionView.list)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _ListRow(
                game: visible[i],
                onTap: () => _openDetail(visible[i]),
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
    );
  }

  /// The 3D view: header and filters, then the shelf over the focused game's
  /// art, then its action bar.
  Widget _flowBody(
    List<GameEntry> visible,
    bool compact,
    bool short,
    double pad,
  ) {
    final index = visible.isEmpty ? 0 : _flowIndex.clamp(0, visible.length - 1);
    final focused = visible.isEmpty ? null : visible[index];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (focused != null) _Backdrop(game: focused),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                pad,
                compact || short ? 16 : 28,
                pad,
                0,
              ),
              child: _header(compact),
            ),
            const SizedBox(height: 14),
            _filters(pad),
            if (focused == null)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 32, pad, 0),
                child: _noMatch(),
              )
            else ...[
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final h = (c.maxHeight * (short ? 0.92 : 0.84)).clamp(
                      96.0,
                      440.0,
                    );
                    final w = (h * 0.7).clamp(
                      64.0,
                      c.maxWidth * (compact ? 0.56 : 0.34),
                    );
                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 0 : pad,
                      ),
                      child: CoverFlow(
                        count: visible.length,
                        index: index,
                        itemSize: Size(w, w / 0.7),
                        showArrows: !compact,
                        semanticLabel: 'Games',
                        onIndexChanged: (i) => setState(() => _flowIndex = i),
                        onActivate: (i) => _openDetail(visible[i]),
                        itemBuilder: (context, i, front) => GameCover(
                          gameId: visible[i].id,
                          title: visible[i].title,
                          system: shortSystemLabel(visible[i].system),
                          selected: front,
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (!short)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Text(
                    '${(index + 1).toString().padLeft(2, '0')}  /  '
                    '${visible.length.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: Tokens.body(
                      size: 11,
                      weight: FontWeight.w700,
                      ls: 1.4,
                      color: Tokens.muted,
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, compact ? 12 : 24),
                child: _FlowBar(
                  game: focused,
                  state: state,
                  compact: compact,
                  short: short,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _noMatch() => Text(
    'No games match. Try another filter or search.',
    style: Tokens.body(size: 13, color: Tokens.muted),
  );

  Widget _header(bool compact) {
    final search = OrbitSearch(
      controller: _search,
      onChanged: (_) => setState(() => _flowIndex = 0),
      hint: compact ? 'Search' : 'Search your games',
      shortcutLabel: compact ? null : 'Ctrl K',
    );
    return Row(
      children: [
        Expanded(
          child: Focus(focusNode: _searchFocus, child: search),
        ),
        const SizedBox(width: 12),
        CollectionViewSwitch(value: _view, onChanged: _setView),
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
    onPressed: () => setState(() {
      _sort = _sort == _Sort.recent ? _Sort.title : _Sort.recent;
      _flowIndex = 0;
    }),
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
        onTap: () => setState(() {
          _filter = id;
          _flowIndex = 0;
        }),
      ),
    );
    // Filters scroll; sort stays put at the end, in every view.
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: pad, right: 8),
              children: [
                chip('all', 'All · ${state.games.length}'),
                if (favorites > 0) chip('favorites', 'Favorites · $favorites'),
                for (final s in systems) chip(s, systemLabel(s)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: pad - 8),
            child: _sortButton(),
          ),
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

    final content = compact
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
          );
    final radius = BorderRadius.circular(Tokens.dockPanelRadius);
    // The game's own art, blurred, behind the card: Resume opens on the game,
    // not on a grey panel.
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        children: [
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Transform.scale(
                scale: 1.4,
                child: GameCover(
                  gameId: game.id,
                  title: '',
                  system: '',
                  radius: 0,
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xE6101B2B), Color(0x99101B2B)],
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.all(compact || short ? 14 : 20),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: Tokens.lineStrong),
            ),
            child: content,
          ),
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
    return FocusGlow(
      onTap: onTap,
      radius: Tokens.radiusCover,
      semanticLabel: game.title,
      semanticHint: semanticsHint,
      child: Padding(
        padding: const EdgeInsets.all(2),
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
    );
  }
}

/// The focused game's art, blurred and darkened behind the 3D shelf.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.game});

  final GameEntry game;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: ImageFiltered(
              key: ValueKey(game.id),
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Opacity(
                opacity: 0.55,
                child: Transform.scale(
                  scale: 1.3,
                  child: GameCover(
                    gameId: game.id,
                    title: '',
                    system: '',
                    radius: 0,
                  ),
                ),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xCC060B14),
                  Color(0x66060B14),
                  Color(0xF2060B14),
                ],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the 3D shelf: what the focused game is, and its one action.
class _FlowBar extends StatelessWidget {
  const _FlowBar({
    required this.game,
    required this.state,
    required this.compact,
    required this.short,
  });

  final GameEntry game;
  final AppState state;
  final bool compact;

  /// Little vertical room: one row, so the shelf keeps its space.
  final bool short;

  @override
  Widget build(BuildContext context) {
    final played = game.lastPlayedMs > 0;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!short) ...[
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Tokens.systemLabelBg,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: Tokens.systemLabelBd),
                  ),
                  child: Text(
                    shortSystemLabel(game.system),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(
                      size: 10,
                      weight: FontWeight.w700,
                      color: Tokens.systemLabelFg,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  played
                      ? lastPlayedLabel(game.lastPlayedMs)
                      : 'Not played yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(size: 12, color: Tokens.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Text(
          game.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tokens.display(
            size: short ? 16 : (compact ? 20 : 26),
            weight: FontWeight.w600,
          ),
        ),
      ],
    );
    final primary = OrbitPrimary(
      label: played ? 'Resume' : 'Play',
      expanded: compact && !short,
      minHeight: short ? 40 : (compact ? 48 : 52),
      onPressed: () => launchGame(context, state, game, resume: played),
    );
    return Container(
      padding: EdgeInsets.all(short ? 10 : (compact ? 14 : 18)),
      decoration: BoxDecoration(
        color: const Color(0xB30B1421),
        borderRadius: BorderRadius.circular(Tokens.dockPanelRadius),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: compact && !short
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [info, const SizedBox(height: 12), primary],
            )
          : Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                primary,
              ],
            ),
    );
  }
}

/// A game as one row: small cover, title, system and when it was played.
class _ListRow extends StatelessWidget {
  const _ListRow({required this.game, required this.onTap});

  final GameEntry game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusGlow(
      onTap: onTap,
      lift: 1.005,
      semanticLabel: game.title,
      semanticHint: 'Open details',
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0x0CDDE6F4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Tokens.line),
        ),
        child: Row(
          children: [
            // Too small for the cover's own caption; the title is beside it.
            GameCover(
              gameId: game.id,
              title: '',
              system: '',
              width: 42,
              height: 58,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(size: 14, weight: FontWeight.w600),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${systemLabel(game.system)} · '
                    '${game.lastPlayedMs > 0 ? lastPlayedLabel(game.lastPlayedMs) : 'Not played yet'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Tokens.body(size: 12, color: Tokens.muted),
                  ),
                ],
              ),
            ),
            if (game.favorite)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  Icons.favorite,
                  size: 16,
                  color: Tokens.systemLabelFg,
                ),
              ),
            const Icon(Icons.chevron_right, color: Tokens.muted),
          ],
        ),
      ),
    );
  }
}
