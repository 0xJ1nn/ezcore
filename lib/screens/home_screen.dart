import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
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
import '../widgets/orbit_chrome.dart';
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
/// Search, the view switch, Add games, the tabs (Time capsule, Favorites,
/// All systems, then one per system) and sort sit in the same place in every
/// view, on every screen size.
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

enum _Sort {
  recent('Recently played'),
  title('A–Z'),
  system('By system');

  const _Sort(this.label);
  final String label;
}

/// Tab ids that are not a system id.
const _capsuleTab = 'capsule';
const _favoritesTab = 'favorites';
const _allTab = 'all';

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'library search');
  String _filter = _allTab; // or _capsuleTab, _favoritesTab, a system id
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
      switch (_filter) {
        case _capsuleTab:
          if (g.lastPlayedMs <= 0) return false;
        case _favoritesTab:
          if (!g.favorite) return false;
        case _allTab:
          break;
        default:
          if (g.system != _filter) return false;
      }
      if (q.isEmpty) return true;
      return g.title.toLowerCase().contains(q) ||
          systemLabel(g.system).toLowerCase().contains(q);
    }).toList();
    int byTitle(GameEntry a, GameEntry b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase());
    int byPlay(GameEntry a, GameEntry b) {
      final c = b.lastPlayedMs.compareTo(a.lastPlayedMs);
      return c != 0 ? c : byTitle(a, b);
    }

    // The time capsule is a history: always the latest first.
    final sort = _filter == _capsuleTab ? _Sort.recent : _sort;
    out.sort(switch (sort) {
      _Sort.recent => byPlay,
      _Sort.title => byTitle,
      _Sort.system => (a, b) {
        final c = systemLabel(a.system).compareTo(systemLabel(b.system));
        return c != 0 ? c : byTitle(a, b);
      },
    });
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
    // Resume and Continue belong to the whole collection: with a tab or a
    // search narrowing it, only the matching games show.
    final everything = _filter == _allTab && _search.text.trim().isEmpty;
    final last = everything ? lastPlayed(games) : null;
    final recent = [
      if (everything)
        for (final g in games)
          if (g.lastPlayedMs > 0 && g.id != last?.id) g,
    ]..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, compact || short ? 16 : 28, pad, 0),
          sliver: SliverToBoxAdapter(child: _header(compact, short)),
        ),
        // The tabs sit right under the search, as in 3D, so they are never
        // below the fold.
        SliverPadding(
          padding: EdgeInsets.only(top: short ? 6 : 14),
          sliver: SliverToBoxAdapter(child: _filters(pad, compact)),
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
        if (last != null || recent.isNotEmpty) _sectionTitle('All games', pad),
        if (visible.isEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 32, pad, 48),
            sliver: SliverToBoxAdapter(child: _noMatch()),
          )
        else if (_grouped)
          for (final (i, group) in _bySystem(visible).indexed) ...[
            _systemHeading(group, pad, first: i == 0),
            _gamesSliver(group, compact, pad, top: 0),
          ]
        else
          _gamesSliver(visible, compact, pad),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }

  /// Sorted by system with more than one system showing: Grid and List get
  /// a heading per system.
  bool get _grouped =>
      _sort == _Sort.system &&
      _filter != _capsuleTab &&
      {for (final g in state.games) g.system}.length > 1;

  /// [games] (already sorted by system) cut into one run per system.
  List<List<GameEntry>> _bySystem(List<GameEntry> games) {
    final out = <List<GameEntry>>[];
    for (final g in games) {
      if (out.isEmpty || out.last.first.system != g.system) out.add([]);
      out.last.add(g);
    }
    return out;
  }

  Widget _systemHeading(
    List<GameEntry> group,
    double pad, {
    required bool first,
  }) {
    final label = systemLabel(group.first.system);
    final count = group.length == 1 ? '1 game' : '${group.length} games';
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, first ? 20 : 30, pad, 12),
      sliver: SliverToBoxAdapter(
        child: Semantics(
          header: true,
          label: '$label, $count',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.display(size: 17, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(count, style: Tokens.body(size: 12, color: Tokens.muted)),
            ],
          ),
        ),
      ),
    );
  }

  /// [games] as a grid or a list, per the view switch.
  Widget _gamesSliver(
    List<GameEntry> games,
    bool compact,
    double pad, {
    double top = 16,
  }) {
    if (_view == CollectionView.list) {
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, top, pad, 0),
        sliver: SliverList.separated(
          itemCount: games.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) =>
              _ListRow(game: games[i], onTap: () => _openDetail(games[i])),
        ),
      );
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, top, pad, 0),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: compact ? 130 : 176,
          mainAxisSpacing: 18,
          crossAxisSpacing: compact ? 12 : 18,
          childAspectRatio: 0.58,
        ),
        itemCount: games.length,
        itemBuilder: (context, i) => _Tile(
          game: games[i],
          footnote: shortSystemLabel(games[i].system),
          onTap: () => _openDetail(games[i]),
          semanticsHint: 'Open details',
        ),
      ),
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
    final hints = !compact && !short && _keyboardDesktop;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (focused != null) _Backdrop(game: focused),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, short ? 8 : 18, pad, 0),
              child: _header(compact, short),
            ),
            SizedBox(height: short ? 6 : 14),
            _filters(pad, compact),
            if (focused == null)
              Padding(
                padding: EdgeInsets.fromLTRB(pad, 32, pad, 0),
                child: _noMatch(),
              )
            else ...[
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    // Room for the cover and its reflection on the floor.
                    final h = (c.maxHeight * (short ? 0.80 : 0.70)).clamp(
                      90.0,
                      420.0,
                    );
                    final w = (h * 0.72).clamp(
                      60.0,
                      c.maxWidth * (compact ? 0.52 : 0.22),
                    );
                    return CoverFlow(
                      count: visible.length,
                      index: index,
                      itemSize: Size(w, w / 0.72),
                      reflection: !short,
                      autofocus: true,
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
                    );
                  },
                ),
              ),
              if (!short) _PageDots(count: visible.length, index: index),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  pad,
                  short ? 4 : 12,
                  pad,
                  hints ? 14 : (compact ? 12 : 24),
                ),
                child: _FlowBar(
                  game: focused,
                  state: state,
                  compact: compact,
                  short: short,
                  onDetails: () => _openDetail(focused),
                ),
              ),
              if (hints)
                Padding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 18),
                  child: const OrbitKeyHints(
                    hints: [
                      (['←', '→'], 'Browse'),
                      (['↵'], 'Game details'),
                      (['/'], 'Search'),
                      (['1–4'], 'Switch space'),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ],
    );
  }

  /// Desktop with a keyboard: the key hints are worth their room.
  bool get _keyboardDesktop => const {
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  }.contains(defaultTargetPlatform);

  /// Why nothing shows, and what to do about it.
  Widget _noMatch() => Text(
    _search.text.trim().isNotEmpty
        ? 'No games match. Try another filter or search.'
        : switch (_filter) {
            _capsuleTab =>
              'Games you play land here, latest first, so you can jump '
                  'back in.',
            _favoritesTab =>
              'No favorites yet. Tap ♡ on a game to keep it here.',
            _ => 'No games match. Try another filter or search.',
          },
    style: Tokens.body(size: 13, color: Tokens.muted),
  );

  /// "YOUR GAMES. YOUR WAY." over "The collection · N games"; search, the
  /// view switch and Add on the right (below the title on phones).
  Widget _header(bool compact, [bool short = false]) {
    final count = state.games.length;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!short) ...[
          Text(
            'YOUR GAMES. YOUR WAY.',
            style: Tokens.body(
              size: 11,
              weight: FontWeight.w600,
              ls: 4,
              color: Tokens.muted,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                'The collection',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Tokens.display(
                  size: short ? 22 : (compact ? 28 : 40),
                  weight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              count == 1 ? '1 game' : '$count games',
              style: Tokens.body(size: 13, color: Tokens.muted),
            ),
          ],
        ),
      ],
    );
    final search = Focus(
      focusNode: _searchFocus,
      child: OrbitSearch(
        controller: _search,
        onChanged: (_) => setState(() => _flowIndex = 0),
        hint: 'Find a game…',
        shortcutLabel: compact ? null : '/',
      ),
    );
    final add = OrbitIconButton(
      icon: Icons.add,
      tooltip: 'Add games',
      onPressed: _openImport,
    );
    final views = CollectionViewSwitch(value: _view, onChanged: _setView);
    // Very short windows: the games need the room more than the title does.
    if (short) {
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 10),
          views,
          const SizedBox(width: 10),
          add,
        ],
      );
    }
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: title),
              add,
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              views,
            ],
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        const SizedBox(width: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, minWidth: 180),
          child: search,
        ),
        const SizedBox(width: 12),
        views,
        const SizedBox(width: 12),
        add,
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

  /// The sort menu. On phones just its icon, so the tabs keep the room.
  Widget _sortButton(bool compact) => PopupMenuButton<_Sort>(
    tooltip: 'Sort',
    initialValue: _sort,
    color: Tokens.panel,
    onSelected: (v) => setState(() {
      _sort = v;
      _flowIndex = 0;
    }),
    itemBuilder: (_) => [
      for (final v in _Sort.values)
        PopupMenuItem(
          value: v,
          child: Text(v.label, style: Tokens.body(size: 13)),
        ),
    ],
    child: Container(
      height: 40,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x26DDE6F4)),
        color: const Color(0x0ADDE6F4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (compact)
            const Icon(Icons.sort, size: 18, color: Tokens.text)
          else ...[
            Text(_sort.label, style: Tokens.body(size: 12, color: Tokens.text)),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18, color: Tokens.muted),
          ],
        ],
      ),
    ),
  );

  /// Time capsule (what you played, latest first), Favorites, All systems,
  /// then each system you own games for; the sort stays put at the end, in
  /// every view.
  Widget _filters(double pad, bool compact) {
    final systems = {for (final g in state.games) g.system}.toList()
      ..sort((a, b) => systemLabel(a).compareTo(systemLabel(b)));
    Widget tab(String id, String label, [IconData? icon]) => _SystemTab(
      label: label,
      icon: icon,
      active: _filter == id,
      onTap: () => setState(() {
        _filter = id;
        _flowIndex = 0;
      }),
    );
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          Expanded(
            child: ShaderMask(
              // Fade the last tab into the sort instead of cutting it.
              shaderCallback: (r) => const LinearGradient(
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.93, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.only(left: pad - 6, right: 24),
                children: [
                  tab(_capsuleTab, 'Time capsule', Icons.history),
                  tab(_favoritesTab, 'Favorites', Icons.favorite_border),
                  tab(_allTab, 'All systems', Icons.grid_view_rounded),
                  for (final s in systems) tab(s, systemLabel(s)),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: pad),
            child: _sortButton(compact),
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
                  'See systems',
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
    // Clipped: the scaled, blurred art must not spill over the top bar.
    return IgnorePointer(
      child: ClipRect(
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
      ),
    );
  }
}

/// The dock under the 3D shelf: what the front game is, and what you can do
/// with it — favourite it, play it (Resume once you have), and a menu for
/// the rest. Its page also opens from the cover itself.
class _FlowBar extends StatelessWidget {
  const _FlowBar({
    required this.game,
    required this.state,
    required this.compact,
    required this.short,
    required this.onDetails,
  });

  final GameEntry game;
  final AppState state;
  final bool compact;

  /// Little vertical room: one row, so the shelf keeps its space.
  final bool short;
  final VoidCallback onDetails;

  String get _size {
    final b = game.fileSize;
    if (b <= 0) return 'unknown size';
    if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(1)} GB';
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(b / 1024).ceil()} KB';
  }

  @override
  Widget build(BuildContext context) {
    final played = game.lastPlayedMs > 0;
    final file = game.filePath.split(RegExp(r'[\\/]')).last;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Tokens.systemLabelBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x66007BFF)),
      ),
      child: Text(
        systemLabel(game.system).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Tokens.body(
          size: 11,
          weight: FontWeight.w700,
          ls: 1.2,
          color: Tokens.systemLabelFg,
        ),
      ),
    );
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!short) ...[
          Row(
            children: [
              Flexible(child: chip),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  '·  ${game.extension}  ·  $_size',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Tokens.body(size: 13, color: Tokens.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Text(
          game.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Tokens.display(
            size: short ? 16 : (compact ? 22 : 30),
            weight: FontWeight.w600,
          ),
        ),
        if (!short && !compact) ...[
          const SizedBox(height: 6),
          Text(
            played
                ? 'Last played ${lastPlayedLabel(game.lastPlayedMs).toLowerCase()} · picks up where you left off'
                : '$file · ready to play',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.body(size: 13, color: Tokens.muted),
          ),
        ],
      ],
    );
    final big = !compact && !short;
    final primary = OrbitPrimary(
      label: played ? 'Resume' : "Let's play",
      expanded: compact && !short,
      minHeight: short ? 40 : (big ? 60 : 50),
      onPressed: () => launchGame(context, state, game, resume: played),
    );
    final heart = _SquareButton(
      size: short ? 40 : (big ? 60 : 50),
      tooltip: game.favorite ? 'Remove from favorites' : 'Add to favorites',
      icon: game.favorite ? Icons.favorite : Icons.favorite_border,
      color: game.favorite ? Tokens.systemLabelFg : Tokens.text,
      onPressed: () => state.toggleFavorite(game.id),
    );
    final more = PopupMenuButton<String>(
      tooltip: 'More',
      color: Tokens.panel,
      onSelected: (v) => switch (v) {
        'page' => onDetails(),
        'start' => launchGame(context, state, game),
        _ => null,
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'page',
          child: Text('Game page', style: Tokens.body(size: 13)),
        ),
        if (played)
          PopupMenuItem(
            value: 'start',
            child: Text('Play from start', style: Tokens.body(size: 13)),
          ),
      ],
      child: _SquareButton(
        size: short ? 40 : (big ? 60 : 50),
        icon: Icons.more_horiz,
        color: Tokens.text,
      ),
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!short) ...[heart, const SizedBox(width: 12)],
        if (compact && !short) Expanded(child: primary) else primary,
        const SizedBox(width: 12),
        more,
      ],
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: short ? 12 : (compact ? 16 : 30),
        vertical: short ? 10 : (compact ? 14 : 22),
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(compact ? 18 : 26),
        border: Border.all(color: const Color(0x4D3D95FF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE60E1828), Color(0xCC0A1220)],
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x33007BFF), blurRadius: 30, spreadRadius: -6),
        ],
      ),
      child: compact && !short
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 12),
                Row(
                  children: [
                    heart,
                    const SizedBox(width: 10),
                    Expanded(child: primary),
                    const SizedBox(width: 10),
                    more,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 16),
                actions,
              ],
            ),
    );
  }
}

/// A square outlined icon button (the dock's heart and menu).
class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.size,
    required this.icon,
    required this.color,
    this.tooltip,
    this.onPressed,
  });

  final double size;
  final IconData icon;
  final Color color;
  final String? tooltip;

  /// Null when a parent (a menu button) handles the press.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.24),
        border: Border.all(color: const Color(0x33DDE6F4)),
        color: const Color(0x0FDDE6F4),
      ),
      child: Icon(icon, color: color, size: size * 0.4),
    );
    if (onPressed == null) return box;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(size * 0.24),
          onTap: onPressed,
          child: box,
        ),
      ),
    );
  }
}

/// A filter tab: icon and label, lit with an underline when chosen.
class _SystemTab extends StatelessWidget {
  const _SystemTab({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : Tokens.muted;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: Tokens.fastDur,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: active ? const Color(0x1F007BFF) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: active ? Tokens.accent : Colors.transparent,
                width: 2.5,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 17,
                  color: active ? Tokens.systemLabelFg : Tokens.muted,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: Tokens.body(
                  size: 13.5,
                  weight: active ? FontWeight.w600 : FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where you are on the shelf: dots for a short shelf, a count for a long
/// one.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: 10);
    if (count > 12) {
      return Text(
        '${(index + 1).toString().padLeft(2, '0')}  /  ${count.toString().padLeft(2, '0')}',
        textAlign: TextAlign.center,
        style: Tokens.body(
          size: 11,
          weight: FontWeight.w700,
          ls: 1.4,
          color: Tokens.muted,
        ),
      );
    }
    return Semantics(
      label: 'Game ${index + 1} of $count',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: Tokens.fastDur,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == index ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: i == index ? Tokens.accent : const Color(0x40DDE6F4),
                boxShadow: i == index
                    ? const [BoxShadow(color: Color(0x80007BFF), blurRadius: 8)]
                    : null,
              ),
            ),
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
