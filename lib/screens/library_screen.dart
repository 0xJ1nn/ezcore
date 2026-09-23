import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../models/game_entry.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'cheats_screen.dart';
import 'game_detail_screen.dart';
import 'import_screen.dart';
import 'player_screen.dart';

/// Orbit Library — the collection, in the shape the studio plate draws it:
///
/// * desktop      — cover flow + full game dock (stats + actions)
/// * tablet       — "Continue playing" / "Recently added" hub rows
/// * phone landscape — compact rail layout, short cover flow, compact dock
/// * phone portrait  — search, All/Favorites/Recent, featured game,
///                     bottom "Continue playing" row
///
/// Every layout shares one data path (`filtered`, `_play`, `_openDetail`)
/// so behaviour cannot drift between screen sizes. All functionality from
/// the previous CoverFlow library is preserved: search, system filter,
/// favorites, import, detail, play, remove.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.state,
    this.onGo,
    this.initialFilter,
  });
  final AppState state;
  final ValueChanged<String>? onGo;
  final String? initialFilter;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final searchCtrl = TextEditingController();
  final searchFocus = FocusNode();
  // A narrow viewport fraction puts several covers on screen, the way the
  // studio plate's carousel does; a wide one showed only the neighbours'
  // edges. The portrait plate instead shows one dominant cover, so it owns
  // a second, wider-framed controller.
  final pageCtrl = PageController(viewportFraction: 0.24);
  final portraitCtrl = PageController(viewportFraction: 0.62);
  String query = '';
  String filter =
      'All systems'; // All systems | Favorites | system id | core:<id>
  String tab = 'all'; // all | favorites | recent
  String view = 'flow';
  int index = 0;

  @override
  void initState() {
    super.initState();
    final layout = widget.state.settings['layout'];
    if (layout == 'grid' || layout == 'flow') view = layout as String;
    final initial = widget.initialFilter;
    if (initial != null && initial.isNotEmpty) {
      if (initial == 'Favorites') {
        tab = 'favorites';
      } else {
        filter = initial;
      }
    }
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    searchFocus.dispose();
    pageCtrl.dispose();
    portraitCtrl.dispose();
    super.dispose();
  }

  /// Games after tab + system filter + search.
  ///
  /// "Recent" is honest: it is exactly the games with a real play stamp,
  /// newest first. There is no completion or play-time data to invent.
  List<GameEntry> get filtered {
    final games = widget.state.games.where((g) {
      if (tab == 'favorites' && !g.favorite) return false;
      if (tab == 'recent' && g.lastPlayedMs <= 0) return false;
      if (tab == 'all' &&
          filter != 'All systems' &&
          filter != 'Favorites' &&
          filter != 'vault') {
        if (filter.startsWith('core:')) {
          final coreId = filter.substring(5);
          if (g.coreId != coreId) {
            // Also match by compatible extension, so games whose core was
            // never chosen still appear under that core.
            final compat = widget.state.registry.catalog
                .where((m) => m.id == coreId)
                .firstOrNull;
            if (compat == null) return false;
            final exts = compat.extensions.map((e) => e.toLowerCase()).toSet();
            if (!exts.contains(g.extension.toLowerCase())) return false;
          }
        } else if (g.system != filter) {
          return false;
        }
      }
      if (query.isNotEmpty &&
          !g.title.toLowerCase().contains(query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
    if (tab == 'recent') {
      games.sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    }
    return games;
  }

  /// Games with a real play stamp, newest first — "Continue playing".
  List<GameEntry> get continuePlaying {
    final list = widget.state.games.where((g) => g.lastPlayedMs > 0).toList()
      ..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    return list;
  }

  /// Most recently imported games — `AppState` appends on import, so the
  /// tail of the list is genuinely the newest.
  List<GameEntry> get recentlyAdded => widget.state.games.reversed.toList();

  List<String> get systems {
    final s = <String>{for (final g in widget.state.games) g.system};
    final out = s.toList()..sort();
    return out;
  }

  void _move(int delta) {
    final list = filtered;
    if (list.isEmpty) return;
    setState(() {
      index = (index + delta).clamp(0, list.length - 1);
    });
    // Animate whichever carousel this layout actually shows.
    final ctrl = Layout.of(context) == OrbitLayout.phonePortrait
        ? portraitCtrl
        : pageCtrl;
    if (ctrl.hasClients) {
      ctrl.animateToPage(index, duration: Tokens.easeDur, curve: Tokens.ease);
    }
  }

  void _setFilter(String next) {
    setState(() {
      if (next == 'Favorites') {
        // Favorites is a tab, not a system value. Keeping one vocabulary
        // prevents the desktop/tablet chip from selecting a value that the
        // shared `filtered` predicate intentionally ignores.
        tab = 'favorites';
        filter = 'All systems';
      } else {
        tab = 'all';
        filter = next;
      }
      index = 0;
    });
  }

  void _setTab(String next) {
    setState(() {
      tab = next;
      index = 0;
    });
  }

  void _clearFilters() {
    setState(() {
      tab = 'all';
      filter = 'All systems';
      query = '';
      searchCtrl.clear();
      index = 0;
    });
  }

  void _openDetail(GameEntry g) {
    showGameDetail(context, gameId: g.id, state: widget.state);
  }

  void _play(GameEntry game) {
    final compatible = widget.state.registry.compatibleCores(game.extension);
    if (compatible.isEmpty) {
      orbitToast(context, 'No installed core opens this file yet');
      return;
    }
    final current = compatible.where((m) => m.id == game.coreId);
    final effective = current.isNotEmpty ? current.first : compatible.first;
    if (effective.id != game.coreId) {
      widget.state.setCore(game.id, effective.id);
    }
    widget.state.recordPlay(game.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(gameId: game.id, state: widget.state),
      ),
    );
  }

  void _openCheats(GameEntry g) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CheatsScreen(gameId: g.id, state: widget.state),
      ),
    );
  }

  void _openStates(GameEntry g) {
    showGameSlots(context, gameId: g.id, state: widget.state);
  }

  void _openImport() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ImportScreen(state: widget.state)),
    );
  }

  void _gameMenu(GameEntry game) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Tokens.radiusDialog),
        side: const BorderSide(color: Tokens.line),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                game.favorite ? Icons.star : Icons.star_outline,
                color: Tokens.text,
              ),
              title: Text(
                game.favorite ? 'Unfavorite' : 'Favorite',
                style: Tokens.body(),
              ),
              onTap: () {
                widget.state.toggleFavorite(game.id);
                Navigator.of(context).pop();
                orbitToast(
                  context,
                  game.favorite
                      ? 'Removed from favorites'
                      : 'Added to your favorites',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Tokens.text),
              title: Text('Remove from library', style: Tokens.body()),
              subtitle: Text(
                'Your file stays on disk',
                style: Tokens.body(size: 11, color: Tokens.muted),
              ),
              onTap: () {
                widget.state.removeGame(game.id);
                Navigator.of(context).pop();
                setState(() => index = 0);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final osPad = Tokens.osPad(
      MediaQuery.of(context).size.width,
      portrait: layout == OrbitLayout.phonePortrait,
    );
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final list = filtered;
        if (index >= list.length) index = list.isEmpty ? 0 : list.length - 1;
        final selected = list.isEmpty ? null : list[index];
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _move(1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _move(-1),
            const SingleActivator(LogicalKeyboardKey.slash): () {
              searchFocus.requestFocus();
            },
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
              searchFocus.requestFocus();
            },
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
              searchFocus.requestFocus();
            },
            const SingleActivator(LogicalKeyboardKey.enter): () {
              if (selected != null) _openDetail(selected);
            },
          },
          child: Focus(
            autofocus: true,
            child: switch (layout) {
              OrbitLayout.desktop => _desktop(list, selected, osPad),
              OrbitLayout.tablet => _hub(osPad),
              OrbitLayout.phoneLandscape => _phoneLandscape(
                list,
                selected,
                osPad,
              ),
              OrbitLayout.phonePortrait => _portrait(list, selected, osPad),
            },
          ),
        );
      },
    );
  }

  // ---- Shared pieces -------------------------------------------------------

  Widget _search({double? width, String? hint, String? shortcut}) {
    final box = OrbitSearch(
      controller: searchCtrl,
      hint: hint ?? 'Search games, systems, or genres…',
      shortcutLabel: shortcut,
      onChanged: (v) => setState(() {
        query = v;
        index = 0;
      }),
    );
    // Flexible by default: inside a header Row the field must give up
    // space rather than overflow a narrow phone.
    return width == null
        ? Expanded(child: box)
        : SizedBox(width: width, child: box);
  }

  Widget _viewSwitcher() {
    return OrbitSwitcher(
      view: view,
      onView: (v) {
        setState(() => view = v);
        widget.state.setSetting('layout', v);
      },
    );
  }

  Widget _importButton() {
    // Tooltip text is part of the existing UI contract (tests and
    // accessibility both key off "Import").
    return OrbitIconButton(
      icon: Icons.add,
      tooltip: 'Import',
      onPressed: _openImport,
    );
  }

  /// The big title block: "The collection  ·  N games" + standfirst.
  Widget _titleBlock(String countLabel, {bool big = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                'The collection',
                style: Tokens.display(
                  size: big ? Tokens.screenTitle : 22,
                  weight: FontWeight.w500,
                  ls: -1.0,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Text(countLabel, style: Tokens.body(size: 12, color: Tokens.muted)),
          ],
        ),
        const SizedBox(height: 4),
        Text('Play. Preserve. Anywhere.', style: Tokens.standfirst),
      ],
    );
  }

  Widget _strip(double osPad) {
    final chips = <Widget>[
      OrbitChip(
        label: 'Time capsule',
        icon: Icons.history_outlined,
        active: false,
        onTap: () => widget.onGo?.call('vault'),
      ),
      OrbitChip(
        label: 'Favorites',
        icon: Icons.favorite_outline,
        active: tab == 'favorites',
        onTap: () =>
            tab == 'favorites' ? _setTab('all') : _setFilter('Favorites'),
      ),
      // "Recent" lives here as well as in the phone tabs, so every layout
      // offers the same filter vocabulary.
      OrbitChip(
        label: 'Recent',
        icon: Icons.schedule,
        active: tab == 'recent',
        onTap: () => tab == 'recent' ? _setTab('all') : _setTab('recent'),
      ),
      OrbitChip(
        label: 'All systems',
        active: tab == 'all' && filter == 'All systems',
        onTap: () => _setFilter('All systems'),
      ),
      Container(
        width: 1,
        height: 18,
        color: Tokens.line,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      ),
      for (final s in systems)
        OrbitChip(
          label: shortSystemLabel(s),
          active: tab == 'all' && filter == s,
          onTap: () => _setFilter(s),
        ),
      // Per installed core shortcuts (short + id), mirrors web strip.
      for (final m in widget.state.registry.installedCores)
        OrbitChip(
          label: _shortFor(m.id),
          sub: m.id,
          active: tab == 'all' && filter == 'core:${m.id}',
          onTap: () => _setFilter('core:${m.id}'),
        ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(osPad, 12, osPad, 4),
      child: ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.96, 1.0],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chips),
        ),
      ),
    );
  }

  String _shortFor(String id) {
    const shorts = {
      'pocketbit': 'GB',
      'gambatte': 'GBC',
      'advancebit': 'GBA',
      'nesbyte': 'NES',
      'superfx': 'SNES',
      'blastproc': 'MD',
      'joystick': '2600',
      'realmode': 'DOS',
      'cardcon': 'PCE',
      'geometry1': 'PS',
      'rcp64': 'N64',
      'dualscreen': 'DS',
      'portcomp': 'PSP',
      'dreamarc': 'DC',
      'powercube': 'GC',
      'twinsh': 'SAT',
      'coinbox': 'ARC',
      'pointclick': 'ADV',
    };
    return shorts[id] ?? id.substring(0, math.min(3, id.length)).toUpperCase();
  }

  String _countLabel(int n) => n == 1 ? '1 game' : '$n games';

  Widget _empty() {
    final hasGames = widget.state.games.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'A little quiet in here.',
              style: Tokens.display(
                size: 22,
                weight: FontWeight.w500,
                ls: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasGames
                  ? 'No titles match. Try another system or clear your search.'
                  : 'Import your own dumps to start your collection.',
              style: Tokens.body(size: 12, color: Tokens.muted, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (hasGames)
              OrbitSecondary(label: 'Clear filters', onPressed: _clearFilters)
            else
              OrbitPrimary(
                label: 'Import a folder',
                icon: Icons.add,
                onPressed: _openImport,
              ),
          ],
        ),
      ),
    );
  }

  // ---- Desktop -------------------------------------------------------------

  Widget _desktop(List<GameEntry> list, GameEntry? selected, double osPad) {
    if (list.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(osPad, 22, osPad, 0),
            child: Row(
              children: [
                Expanded(
                  child: _titleBlock(_countLabel(widget.state.games.length)),
                ),
                _search(width: 260, shortcut: 'Ctrl K'),
                const SizedBox(width: 8),
                _viewSwitcher(),
                const SizedBox(width: 8),
                _importButton(),
              ],
            ),
          ),
          _strip(osPad),
          Expanded(child: _empty()),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(osPad, 22, osPad, 0),
          child: Row(
            children: [
              Expanded(child: _titleBlock(_countLabel(list.length))),
              _search(width: 260, shortcut: 'Ctrl K'),
              const SizedBox(width: 8),
              _viewSwitcher(),
              const SizedBox(width: 8),
              _importButton(),
            ],
          ),
        ),
        _strip(osPad),
        Expanded(
          child: view == 'grid'
              ? _grid(list, osPad)
              : _flowStage(list, selected, osPad, desktop: true),
        ),
      ],
    );
  }

  // ---- Phone landscape -----------------------------------------------------

  Widget _phoneLandscape(
    List<GameEntry> list,
    GameEntry? selected,
    double osPad,
  ) {
    if (list.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(osPad, 8, osPad, 0),
            child: Row(
              children: [
                Expanded(
                  child: _titleBlock(_countLabel(list.length), big: false),
                ),
                _search(width: 200, hint: 'Search games…'),
                const SizedBox(width: 8),
                _importButton(),
              ],
            ),
          ),
          Expanded(child: _empty()),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(osPad, 8, osPad, 0),
          child: Row(
            children: [
              Expanded(
                child: _titleBlock(_countLabel(list.length), big: false),
              ),
              _search(width: 200, hint: 'Search games…'),
              const SizedBox(width: 8),
              _viewSwitcher(),
              const SizedBox(width: 8),
              _importButton(),
            ],
          ),
        ),
        Expanded(
          child: view == 'grid'
              ? _grid(list, osPad)
              : _flowStage(list, selected, osPad, desktop: false),
        ),
      ],
    );
  }

  // ---- Phone portrait ------------------------------------------------------

  Widget _portrait(List<GameEntry> list, GameEntry? selected, double osPad) {
    final playable = selected != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(osPad, 10, osPad, 0),
          child: Row(
            children: [
              _search(hint: 'Search games…'),
              const SizedBox(width: 8),
              _viewSwitcher(),
              const SizedBox(width: 8),
              _importButton(),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(osPad, 12, osPad, 8),
          child: OrbitTabs(value: tab, onChanged: _setTab),
        ),
        Expanded(
          child: view == 'grid'
              ? _grid(list, osPad)
              : list.isEmpty
              ? _empty()
              : _portraitFeatured(list, selected, osPad),
        ),
        if (playable) _continueRow(osPad),
      ],
    );
  }

  /// Featured cover + dots + title + play actions (the portrait plate).
  ///
  /// The cover stage flexes: the title, dots and CTA keep their space, and
  /// the cover takes whatever is left. A fixed height here overflowed on
  /// short phones once the shell's top and bottom bars were accounted for.
  Widget _portraitFeatured(
    List<GameEntry> list,
    GameEntry? selected,
    double osPad,
  ) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverH = math.min(constraints.maxHeight, 320.0);
              final coverW = coverH * 0.72;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0.5, 0.45),
                          radius: 0.6,
                          colors: [
                            Tokens.accent.withValues(alpha: 0.14),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.72],
                        ),
                      ),
                    ),
                  ),
                  PageView.builder(
                    controller: pageCtrl,
                    itemCount: list.length,
                    onPageChanged: (i) => setState(() => index = i),
                    itemBuilder: (context, i) => AnimatedBuilder(
                      animation: portraitCtrl,
                      builder: (context, child) {
                        double delta = 0;
                        if (portraitCtrl.hasClients &&
                            portraitCtrl.position.haveDimensions) {
                          delta = (i - (portraitCtrl.page ?? index.toDouble()))
                              .clamp(-4.0, 4.0);
                        } else {
                          delta = (i - index).toDouble().clamp(-4.0, 4.0);
                        }
                        final a = delta.abs();
                        if (a > 4) return const SizedBox.shrink();
                        final angle = delta == 0
                            ? 0.0
                            : (delta > 0 ? -14.0 : 14.0) * math.pi / 180;
                        final scale = delta == 0
                            ? 1.0
                            : (0.9 - (a - 1) * 0.05).clamp(0.7, 0.9);
                        final opacity = delta == 0
                            ? 1.0
                            : (0.85 - a * 0.12).clamp(0.3, 0.85);
                        return Opacity(
                          opacity: opacity,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0012)
                              ..rotateY(angle)
                              ..scaleByDouble(scale, scale, 1.0, 1.0),
                            child: GestureDetector(
                              onTap: () {
                                if (i == index) {
                                  _openDetail(list[i]);
                                } else {
                                  portraitCtrl.animateToPage(
                                    i,
                                    duration: Tokens.easeDur,
                                    curve: Tokens.ease,
                                  );
                                }
                              },
                              onLongPress: () => _gameMenu(list[i]),
                              child: GameCover(
                                gameId: list[i].id,
                                title: list[i].title,
                                system: shortSystemLabel(list[i].system),
                                width: coverW,
                                height: coverH,
                                selected: i == index,
                                dimmed: i != index,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned(
                    left: 0,
                    child: _FlowButton(
                      icon: Icons.chevron_left,
                      enabled: index > 0,
                      onTap: () => _move(-1),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    child: _FlowButton(
                      icon: Icons.chevron_right,
                      enabled: index < list.length - 1,
                      onTap: () => _move(1),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _dots(list.length),
        const SizedBox(height: 8),
        if (selected != null)
          Padding(
            padding: EdgeInsets.fromLTRB(osPad, 0, osPad, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  selected.title,
                  style: Tokens.display(
                    size: 20,
                    weight: FontWeight.w500,
                    ls: -0.6,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  shortSystemLabel(selected.system),
                  style: Tokens.body(size: 10, color: Tokens.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OrbitPrimary(
                        label: 'Play',
                        expanded: true,
                        minHeight: 46,
                        onPressed: () => _play(selected),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OrbitRoundButton(
                      icon: Icons.more_horiz,
                      tooltip: 'Game options and details',
                      onPressed: () => _openDetail(selected),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dots(int count) {
    if (count <= 1) return const SizedBox(height: 10);
    final shown = math.min(count, 7);
    return SizedBox(
      height: 14,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < shown; i++)
            AnimatedContainer(
              duration: Tokens.fastDur,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 16 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index ? Tokens.accent : Tokens.separator,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          if (count > shown) ...[
            const SizedBox(width: 6),
            Text('+$count', style: Tokens.body(size: 9, color: Tokens.muted)),
          ],
        ],
      ),
    );
  }

  /// "Continue playing" — real play stamps only, never a placeholder.
  Widget _continueRow(double osPad) {
    final games = continuePlaying;
    if (games.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(osPad, 6, osPad, 2),
          child: OrbitSectionHeader(
            title: 'Continue playing',
            onSeeAll: () => _setTab('recent'),
          ),
        ),
        SizedBox(
          height: 186,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(osPad, 4, osPad, 8),
            itemCount: games.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => GameTile(
              game: games[i],
              width: 96,
              footnote: lastPlayedLabel(games[i].lastPlayedMs),
              onTap: () => _play(games[i]),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Tablet hub ----------------------------------------------------------

  Widget _hub(double osPad) {
    final games = filtered;
    // The two plate sections are enough on their own; a third identical row
    // only appears when the collection is actually being narrowed
    // (a search, a tab, or a system filter), where it earns its place.
    final narrowed =
        query.isNotEmpty || tab != 'all' || filter != 'All systems';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(osPad, 12, osPad, 0),
          child: Row(
            children: [
              _search(hint: 'Search games…'),
              const SizedBox(width: 8),
              _viewSwitcher(),
              const SizedBox(width: 8),
              _importButton(),
            ],
          ),
        ),
        _strip(osPad),
        Expanded(
          child: games.isEmpty
              ? _empty()
              : ListView(
                  padding: EdgeInsets.fromLTRB(osPad, 8, osPad, 20),
                  children: [
                    if (continuePlaying.isNotEmpty) ...[
                      OrbitSectionHeader(
                        title: 'Continue playing',
                        onSeeAll: () => _setTab('recent'),
                      ),
                      const SizedBox(height: 10),
                      _tileRow(
                        continuePlaying,
                        footnote: (g) => lastPlayedLabel(g.lastPlayedMs),
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (recentlyAdded.isNotEmpty) ...[
                      OrbitSectionHeader(
                        title: 'Recently added',
                        onSeeAll: () => _clearFilters(),
                      ),
                      const SizedBox(height: 10),
                      // This row is an import-order snapshot, not a second
                      // view of the currently filtered collection.
                      _tileRow(recentlyAdded, footnote: (g) => _systemNote(g)),
                    ],
                    if (narrowed) ...[
                      const SizedBox(height: 22),
                      OrbitSectionHeader(
                        title: tab == 'favorites'
                            ? 'Favorites'
                            : (tab == 'recent' ? 'Recent' : 'The collection'),
                      ),
                      const SizedBox(height: 10),
                      _tileRow(games, footnote: (g) => _systemNote(g)),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _tileRow(
    List<GameEntry> games, {
    required String Function(GameEntry) footnote,
  }) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: games.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, i) => GameTile(
          game: games[i],
          width: 112,
          footnote: footnote(games[i]),
          onTap: () => _openDetail(games[i]),
        ),
      ),
    );
  }

  String _systemNote(GameEntry g) {
    // Persisted paths may come from Unix or Windows. Keep the persisted
    // format untouched, but never display a full native path in a tile.
    final parts = g.filePath
        .replaceAll('\\', '/')
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    final base = parts.isEmpty ? '' : parts.last;
    return base.isEmpty ? shortSystemLabel(g.system) : base;
  }

  // ---- Cover flow + dock ---------------------------------------------------

  Widget _grid(List<GameEntry> list, double osPad) {
    final dense = widget.state.settings['dense'] == true;
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(osPad, 18, osPad, 24),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: dense ? 120 : 160,
        mainAxisSpacing: 24,
        crossAxisSpacing: 18,
        childAspectRatio: 0.62,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final g = list[i];
        return GestureDetector(
          onTap: () => _openDetail(g),
          onLongPress: () => _gameMenu(g),
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GameCover(
                    gameId: g.id,
                    title: g.title,
                    system: shortSystemLabel(g.system),
                    radius: Tokens.radiusCover,
                  ),
                ),
                if (g.favorite)
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Icon(Icons.star, size: 16, color: Tokens.accent),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _flowStage(
    List<GameEntry> list,
    GameEntry? selected,
    double osPad, {
    required bool desktop,
  }) {
    final height = MediaQuery.of(context).size.height;
    // A short viewport has no room for the reflection echo: it would eat a
    // third of the stage and shrink the covers to stamps.
    final reflectH =
        (!desktop && Layout.isShort(Layout.of(context))) ||
            widget.state.settings['reflection'] == false
        ? 0.0
        : 60.0;
    final budget = desktop ? height * 0.40 : height * 0.46;
    final flowH = (desktop ? budget : math.min(budget, 300.0)).clamp(
      150.0,
      460.0,
    );
    // The cover is what actually has to fit: the stage also holds the
    // reflection echo, so it is part of the budget rather than a bonus.
    final coverH = (flowH - 20 - reflectH).clamp(96.0, 330.0);
    final coverW = coverH * 0.72;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        SizedBox(
          height: flowH,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.5, 0.55),
                      radius: 0.6,
                      colors: [
                        Tokens.accent.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
              PageView.builder(
                controller: portraitCtrl,
                itemCount: list.length,
                onPageChanged: (i) => setState(() => index = i),
                itemBuilder: (context, i) {
                  return AnimatedBuilder(
                    animation: pageCtrl,
                    builder: (context, child) {
                      double delta = 0;
                      // `hasClients` first: inside the shell's IndexedStack
                      // this carousel can build before the PageView has
                      // attached, and `.position` throws when it has not.
                      if (pageCtrl.hasClients &&
                          pageCtrl.position.haveDimensions) {
                        final p = pageCtrl.page ?? index.toDouble();
                        delta = (i - p).clamp(-4.0, 4.0);
                      } else {
                        delta = (i - index).toDouble().clamp(-4.0, 4.0);
                      }
                      final a = delta.abs();
                      if (a > 4) return const SizedBox.shrink();
                      final angle = (delta == 0)
                          ? 0.0
                          : (delta > 0 ? -18.0 : 18.0) * math.pi / 180;
                      final scale = delta == 0
                          ? 1.0
                          : (0.88 - (a - 1) * 0.06).clamp(0.6, 0.88);
                      final opacity = delta == 0
                          ? 1.0
                          : (0.87 - a * 0.13).clamp(0.23, 0.87);
                      return Opacity(
                        opacity: opacity,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012)
                            ..rotateY(angle)
                            ..scaleByDouble(scale, scale, 1.0, 1.0),
                          child: GestureDetector(
                            onTap: () {
                              if (i == index) {
                                _openDetail(list[i]);
                              } else {
                                pageCtrl.animateToPage(
                                  i,
                                  duration: Tokens.easeDur,
                                  curve: Tokens.ease,
                                );
                              }
                            },
                            onLongPress: () => _gameMenu(list[i]),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                GameCover(
                                  gameId: list[i].id,
                                  title: list[i].title,
                                  system: shortSystemLabel(list[i].system),
                                  width: coverW,
                                  height: coverH,
                                  selected: i == index,
                                  dimmed: i != index,
                                ),
                                if (reflectH > 0)
                                  Opacity(
                                    opacity: 0.07,
                                    child: Transform(
                                      alignment: Alignment.topCenter,
                                      transform: Matrix4.identity()
                                        ..scaleByDouble(1.0, -0.35, 1.0, 1.0),
                                      child: GameCover(
                                        gameId: list[i].id,
                                        title: list[i].title,
                                        system: '',
                                        width: coverW,
                                        height: 60,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              Positioned(
                left: osPad,
                child: _FlowButton(
                  icon: Icons.chevron_left,
                  enabled: index > 0,
                  onTap: () => _move(-1),
                ),
              ),
              Positioned(
                right: osPad,
                child: _FlowButton(
                  icon: Icons.chevron_right,
                  enabled: index < list.length - 1,
                  onTap: () => _move(1),
                ),
              ),
            ],
          ),
        ),
        if (desktop)
          Padding(
            padding: EdgeInsets.fromLTRB(osPad, 0, osPad, 4),
            child: Text(
              '${(index + 1).toString().padLeft(2, '0')} / ${list.length.toString().padLeft(2, '0')}',
              style: Tokens.flowCount,
            ),
          ),
        if (selected != null)
          Padding(
            padding: EdgeInsets.fromLTRB(osPad, 0, osPad, 12),
            child: desktop ? _desktopDock(selected) : _compactDock(selected),
          ),
      ],
    );
  }

  /// The studio plate's game dock: cover, copy, real stats, real actions.
  Widget _desktopDock(GameEntry g) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: Tokens.panelGlass,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 84,
                height: 112,
                child: GameCover(
                  gameId: g.id,
                  title: g.title,
                  system: shortSystemLabel(g.system),
                  radius: Tokens.radiusCover,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(child: _dockCopy(g)),
              const SizedBox(width: 18),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OrbitPrimary(
                      label: 'Play',
                      icon: Icons.play_arrow,
                      onPressed: () => _play(g),
                    ),
                    const SizedBox(width: 8),
                    OrbitRoundButton(
                      icon: Icons.more_horiz,
                      tooltip: 'Game options and details',
                      onPressed: () => _openDetail(g),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 300, child: GameStatPanel(game: g)),
              const SizedBox(width: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GameActionRow(
                    game: g,
                    onManage: () => _openDetail(g),
                    onCheats: () => _openCheats(g),
                    onStates: () => _openStates(g),
                    onMore: () => _gameMenu(g),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Short-viewport dock: one row, no stat panel, actions stay reachable
  /// through the More button.
  Widget _compactDock(GameEntry g) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: Tokens.panelGlass,
      child: Row(
        children: [
          Expanded(child: _dockCopy(g, compact: true)),
          const SizedBox(width: 12),
          OrbitPrimary(label: 'Play', minHeight: 42, onPressed: () => _play(g)),
          const SizedBox(width: 8),
          OrbitRoundButton(
            icon: Icons.more_horiz,
            tooltip: 'Game options and details',
            onPressed: () => _openDetail(g),
          ),
        ],
      ),
    );
  }

  Widget _dockCopy(GameEntry g, {bool compact = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SystemLabel(text: shortSystemLabel(g.system)),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: Tokens.separator,
                shape: BoxShape.circle,
              ),
            ),
            Text('.${g.extension}', style: Tokens.gameMeta),
            Container(
              width: 3,
              height: 3,
              decoration: const BoxDecoration(
                color: Tokens.separator,
                shape: BoxShape.circle,
              ),
            ),
            Text(fileSizeLabel(g.fileSize), style: Tokens.gameMeta),
            if (g.favorite)
              const Icon(Icons.star, size: 12, color: Tokens.accent),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          g.title,
          style: compact
              ? Tokens.display(size: 17, weight: FontWeight.w500, ls: -0.4)
              : Tokens.dockTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (!compact) ...[
          const SizedBox(height: 6),
          Text(
            g.stateCount > 0
                ? 'Your dump · ${countLabel(g.stateCount, 'moment')} saved.'
                : 'Your dump · ready to play.',
            style: Tokens.dockBodyStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _FlowButton extends StatelessWidget {
  const _FlowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: Material(
        color: const Color(0xC90A0A0A),
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0x30DDE6F4)),
            ),
            child: Icon(icon, size: 20, color: Tokens.text),
          ),
        ),
      ),
    );
  }
}
