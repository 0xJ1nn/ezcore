import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../models/game_entry.dart';
import '../state/app_state.dart';
import '../theme/cover_flow_style.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/orbit_widgets.dart';
import 'cheats_screen.dart';
import 'game_detail_screen.dart';
import 'import_screen.dart';
import 'player_screen.dart';

/// Orbit Library — the collection, in the shape the studio plate draws it:
///
/// * desktop      — wide cover flow + full game dock (stats + actions)
/// * tablet       — "Continue playing" / "Recently added" hub rows
/// * phone landscape — compact rail layout, short cover flow, compact dock
/// * phone portrait  — search, All/Favorites/Recent, featured game,
///                     bottom "Continue playing" row
/// * tablet portrait — roomy hub with the command rail retained
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
    this.filter,
    this.onFilterChanged,
  });
  final AppState state;
  final ValueChanged<String>? onGo;
  final String? filter;
  final ValueChanged<String?>? onFilterChanged;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final searchCtrl = TextEditingController();
  final searchFocus = FocusNode();
  final libraryFocus = FocusNode(debugLabel: 'library-browser');
  // Each shape gets a viewport pitch that keeps nearby art visible without
  // letting portrait covers overlap. The controller used to drive the page
  // and its animated covers must always be the same instance.
  final desktopFlowCtrl = PageController(viewportFraction: 0.18);
  final landscapeFlowCtrl = PageController(viewportFraction: 0.24);
  final portraitFlowCtrl = PageController(viewportFraction: 0.62);
  OrbitLayout? _lastLayout;
  String query = '';
  String filter =
      'All systems'; // All systems | Favorites | system id | core:<id>
  String tab = 'all'; // all | favorites | recent | continue
  String view = 'flow';
  int index = 0;
  double _pointerScroll = 0;
  bool _snappingReducedMotion = false;

  @override
  void initState() {
    super.initState();
    final layout = widget.state.settings['layout'];
    if (layout == 'grid' || layout == 'flow') view = layout as String;
    final initial = widget.filter;
    if (initial != null && initial.isNotEmpty) {
      _applyCollection(initial);
    }
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    searchFocus.dispose();
    libraryFocus.dispose();
    desktopFlowCtrl.dispose();
    landscapeFlowCtrl.dispose();
    portraitFlowCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      _applyCollection(widget.filter);
      _clearSearch();
      _syncCarouselToIndex();
    }
  }

  void _syncViewPreference() {
    final setting = widget.state.settings['layout'];
    if (setting != 'grid' && setting != 'flow') return;
    final next = setting as String;
    if (view == next) return;
    view = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncCarouselToIndex();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncViewPreference();
    final layout = Layout.of(context);
    if (_lastLayout != layout) {
      if (layout == OrbitLayout.phonePortrait && tab == 'continue') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            tab = 'recent';
            index = 0;
          });
          widget.onFilterChanged?.call('Recent');
          _syncCarouselToIndex();
        });
      } else {
        _syncCarouselToIndex();
      }
    }
    _lastLayout = layout;
  }

  PageController _flowControllerFor(OrbitLayout layout) => switch (layout) {
    OrbitLayout.desktop => desktopFlowCtrl,
    OrbitLayout.phonePortrait => portraitFlowCtrl,
    _ => landscapeFlowCtrl,
  };

  CoverFlowStyle get _flowStyle =>
      CoverFlowStyle.fromSetting(widget.state.settings['coverFlowStyle']);

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  ScrollPhysics get _flowPhysics => _reduceMotion
      ? const ClampingScrollPhysics()
      : const PageScrollPhysics(parent: BouncingScrollPhysics());

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      if (resolved is! PointerScrollEvent) return;
      final delta = resolved.scrollDelta.dx != 0
          ? resolved.scrollDelta.dx
          : resolved.scrollDelta.dy;
      _pointerScroll += delta;
      if (_pointerScroll.abs() < 24) return;
      final direction = _pointerScroll > 0 ? 1 : -1;
      _pointerScroll = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _move(direction);
      });
    });
  }

  void _snapReducedFlow(PageController controller) {
    if (!_reduceMotion ||
        _snappingReducedMotion ||
        !controller.hasClients ||
        filtered.isEmpty) {
      return;
    }
    final current = controller.page ?? controller.position.pixels;
    final target = current.round().clamp(0, filtered.length - 1).toInt();
    if ((current - target).abs() >= 0.001) {
      _snappingReducedMotion = true;
      try {
        controller.jumpToPage(target);
      } finally {
        _snappingReducedMotion = false;
      }
    }
    if (target != index && mounted) setState(() => index = target);
  }

  bool _handleFlowScrollEnd(
    PageController controller,
    ScrollEndNotification notification,
  ) {
    _snapReducedFlow(controller);
    return false;
  }

  Widget _flowViewport({
    required PageController controller,
    required Widget child,
  }) {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) =>
          _handleFlowScrollEnd(controller, notification),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _handlePointerSignal,
        onPointerUp: (_) => _snapReducedFlow(controller),
        child: child,
      ),
    );
  }

  void _syncCarouselToIndex() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final list = filtered;
      if (list.isEmpty) return;
      final controller = _flowControllerFor(Layout.of(context));
      if (controller.hasClients) {
        controller.jumpToPage(index.clamp(0, list.length - 1).toInt());
      }
    });
  }

  void _selectPage(int target) {
    final list = filtered;
    if (list.isEmpty) return;
    final safeTarget = target.clamp(0, list.length - 1).toInt();
    if (safeTarget != index) setState(() => index = safeTarget);
    _animateToPage(safeTarget);
  }

  void _animateToPage(int target) {
    final controller = _flowControllerFor(Layout.of(context));
    if (!controller.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(target);
      return;
    }
    final style = _flowStyle;
    controller.animateToPage(
      target,
      duration: style.settleDuration,
      curve: style.settleCurve,
    );
  }

  void _resetCarousel() => _syncCarouselToIndex();

  /// Games after tab + system filter + search.
  ///
  /// "Recent" is honest: it is exactly the games with a real play stamp,
  /// newest first. There is no completion or play-time data to invent.
  List<GameEntry> get filtered {
    final games = widget.state.games.where((g) {
      if (tab == 'favorites' && !g.favorite) return false;
      if ((tab == 'recent' || tab == 'continue') && g.lastPlayedMs <= 0) {
        return false;
      }
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
    if (tab == 'recent' || tab == 'continue') {
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
    if (filtered.isEmpty) return;
    _selectPage(index + delta);
  }

  void _applyCollection(String? next) {
    switch (next) {
      case 'Favorites':
      case 'favorites':
        tab = 'favorites';
        filter = 'All systems';
      case 'Continue':
      case 'continue':
        tab = 'continue';
        filter = 'All systems';
      case 'Recent':
      case 'recent':
        tab = 'recent';
        filter = 'All systems';
      case null:
      case 'all':
      case 'All systems':
        tab = 'all';
        filter = 'All systems';
      default:
        tab = 'all';
        filter = next;
    }
    index = 0;
  }

  void _notifyCollection() {
    final value = switch (tab) {
      'favorites' => 'Favorites',
      'continue' => 'Continue',
      'recent' => 'Recent',
      _ => filter == 'All systems' ? null : filter,
    };
    widget.onFilterChanged?.call(value);
  }

  void _clearSearch() {
    query = '';
    searchCtrl.clear();
  }

  void _setFilter(String next) {
    setState(() {
      _applyCollection(next);
      _clearSearch();
    });
    _notifyCollection();
    _resetCarousel();
  }

  void _setTab(String next) {
    setState(() {
      _applyCollection(next);
      _clearSearch();
    });
    _notifyCollection();
    _resetCarousel();
  }

  void _clearFilters() {
    setState(() {
      _applyCollection(null);
      query = '';
      searchCtrl.clear();
    });
    _notifyCollection();
    _resetCarousel();
  }

  void _openDetail(GameEntry g) {
    showGameDetail(context, gameId: g.id, state: widget.state);
  }

  void _openSelectedDetail() {
    final list = filtered;
    if (list.isEmpty) return;
    _openDetail(list[index.clamp(0, list.length - 1).toInt()]);
  }

  KeyEventResult _handleLibraryKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.keyK &&
        (keyboard.isControlPressed || keyboard.isMetaPressed)) {
      searchFocus.requestFocus();
      return KeyEventResult.handled;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowRight:
        _move(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _move(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.slash:
        searchFocus.requestFocus();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _openSelectedDetail();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
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
                final oldList = filtered;
                final removedAt = oldList.indexWhere((g) => g.id == game.id);
                widget.state.removeGame(game.id);
                final newLength = filtered.length;
                final nextIndex = removedAt >= 0 && removedAt < index
                    ? index - 1
                    : index;
                Navigator.of(context).pop();
                setState(() {
                  index = newLength == 0
                      ? 0
                      : nextIndex.clamp(0, newLength - 1).toInt();
                });
                _resetCarousel();
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
    final short = Layout.isShort(layout);
    final osPad = Tokens.osPad(
      MediaQuery.of(context).size.width,
      portrait: Layout.isPortrait(layout),
      short_: short,
    );
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        _syncViewPreference();
        final list = filtered;
        final clampedIndex = list.isEmpty
            ? 0
            : index.clamp(0, list.length - 1).toInt();
        if (clampedIndex != index) {
          index = clampedIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _syncCarouselToIndex();
          });
        }
        final selected = list.isEmpty ? null : list[index];
        return Focus(
          focusNode: libraryFocus,
          autofocus: true,
          onKeyEvent: _handleLibraryKey,
          child: switch (layout) {
            OrbitLayout.desktop => _desktop(list, selected, osPad),
            OrbitLayout.tablet => _hub(osPad),
            OrbitLayout.tabletPortrait => _hub(osPad),
            OrbitLayout.phoneLandscape => _phoneLandscape(
              list,
              selected,
              osPad,
            ),
            OrbitLayout.phonePortrait => _portrait(list, selected, osPad),
          },
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
      onChanged: (v) {
        setState(() {
          query = v;
          index = 0;
        });
        _resetCarousel();
      },
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
        if (v == 'flow') _syncCarouselToIndex();
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
            Expanded(
              flex: 3,
              child: Text(
                'The collection',
                style: Tokens.display(
                  size: big ? Tokens.screenTitle : 22,
                  weight: FontWeight.w500,
                  ls: -1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                countLabel,
                style: Tokens.body(size: 12, color: Tokens.muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
        label: 'Capsule',
        icon: Icons.history_outlined,
        active: false,
        onTap: () => widget.onGo?.call('vault'),
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
      for (final core in widget.state.registry.installedCores)
        OrbitChip(
          label: _shortFor(core.id),
          sub: core.id,
          active: tab == 'all' && filter == 'core:${core.id}',
          onTap: () => _setFilter('core:${core.id}'),
        ),
      Container(
        width: 1,
        height: 18,
        color: Tokens.line,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      ),
      OrbitChip(
        label: 'Favorites',
        icon: Icons.favorite_outline,
        active: tab == 'favorites',
        onTap: () =>
            tab == 'favorites' ? _setTab('all') : _setFilter('Favorites'),
      ),
      OrbitChip(
        label: 'Recent',
        icon: Icons.schedule,
        active: tab == 'recent',
        onTap: () => tab == 'recent' ? _setTab('all') : _setTab('recent'),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 360;
        final header = _landscapeHeader(
          list.length,
          osPad,
          stacked: constraints.maxWidth < 600,
        );
        if (compact) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                SizedBox(
                  height: 180,
                  child: list.isEmpty
                      ? _empty()
                      : view == 'grid'
                      ? _grid(list, osPad)
                      : _flowStage(list, selected, osPad, desktop: false),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Expanded(
              child: list.isEmpty
                  ? _empty()
                  : view == 'grid'
                  ? _grid(list, osPad)
                  : _flowStage(list, selected, osPad, desktop: false),
            ),
          ],
        );
      },
    );
  }

  Widget _landscapeHeader(int count, double osPad, {required bool stacked}) {
    final title = _titleBlock(_countLabel(count), big: false);
    if (stacked) {
      return Padding(
        padding: EdgeInsets.fromLTRB(osPad, 8, osPad, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 8),
                _importButton(),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _search(width: 160, hint: 'Search games…'),
                const SizedBox(width: 8),
                _viewSwitcher(),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(osPad, 8, osPad, 0),
      child: Row(
        children: [
          Expanded(child: title),
          _search(width: 200, hint: 'Search games…'),
          const SizedBox(width: 8),
          _viewSwitcher(),
          const SizedBox(width: 8),
          _importButton(),
        ],
      ),
    );
  }

  // ---- Phone portrait ------------------------------------------------------

  Widget _portrait(List<GameEntry> list, GameEntry? selected, double osPad) {
    final playable = selected != null;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 520;
        final controls = _portraitControls(osPad);
        final tabs = Padding(
          padding: EdgeInsets.fromLTRB(osPad, 12, osPad, 8),
          child: OrbitTabs(value: tab, onChanged: _setTab),
        );
        if (compact) {
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                controls,
                tabs,
                SizedBox(
                  height: 240,
                  child: view == 'grid'
                      ? _grid(list, osPad)
                      : list.isEmpty
                      ? _empty()
                      : _portraitFeatured(list, selected, osPad),
                ),
                if (playable) _continueRow(osPad),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            controls,
            tabs,
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
      },
    );
  }

  Widget _portraitControls(double osPad) {
    return Padding(
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
    );
  }

  /// Shared fractional-page treatment for desktop and mobile shelves.
  Widget _flowCard({
    required PageController controller,
    required List<GameEntry> games,
    required int itemIndex,
    required double coverWidth,
    required double coverHeight,
    required CoverFlowStyle style,
    bool reflection = false,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final page = controller.hasClients && controller.position.haveDimensions
            ? controller.page ?? index.toDouble()
            : index.toDouble();
        final rawDelta = itemIndex - page;
        if (rawDelta.abs() > 4) return const SizedBox.shrink();
        final delta = rawDelta.clamp(-4.0, 4.0);
        final distance = delta.abs();

        final angle = -delta.sign * style.rotationDegrees * math.pi / 180;
        final scale = math
            .max(style.minScale, 1 - (1 - style.neighborScale) * distance)
            .toDouble();
        final opacity = math
            .max(style.minOpacity, 1 - (1 - style.neighborOpacity) * distance)
            .toDouble();
        final game = games[itemIndex];
        final matrix = Matrix4.identity();
        if (style.perspective > 0) {
          matrix.setEntry(3, 2, style.perspective);
        }
        matrix
          ..rotateY(angle)
          ..scaleByDouble(scale, scale, 1.0, 1.0);

        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: GestureDetector(
              onTap: () {
                if (itemIndex == index) {
                  _openDetail(game);
                } else {
                  _selectPage(itemIndex);
                }
              },
              onLongPress: () => _gameMenu(game),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GameCover(
                    gameId: game.id,
                    title: game.title,
                    system: shortSystemLabel(game.system),
                    width: coverWidth,
                    height: coverHeight,
                    selected: itemIndex == index,
                    dimmed: itemIndex != index,
                  ),
                  if (reflection)
                    Opacity(
                      opacity: 0.07,
                      child: Transform(
                        alignment: Alignment.topCenter,
                        transform: Matrix4.identity()
                          ..scaleByDouble(1.0, -0.35, 1.0, 1.0),
                        child: GameCover(
                          gameId: game.id,
                          title: game.title,
                          system: '',
                          width: coverWidth,
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
    final style = MediaQuery.disableAnimationsOf(context)
        ? CoverFlowStyle.flat
        : _flowStyle;
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final coverH = math.min(constraints.maxHeight, 320.0);
              final slotW =
                  constraints.maxWidth * portraitFlowCtrl.viewportFraction;
              final coverW = math.min(coverH * 0.72, slotW * 0.88);
              final cardH = math.min(coverH, coverW / 0.72);
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
                  _flowViewport(
                    controller: portraitFlowCtrl,
                    child: PageView.builder(
                      controller: portraitFlowCtrl,
                      physics: _flowPhysics,
                      pageSnapping: !_reduceMotion,
                      allowImplicitScrolling: !_reduceMotion,
                      scrollBehavior: const _CoverFlowScrollBehavior(),
                      itemCount: list.length,
                      onPageChanged: (i) {
                        if (i != index) setState(() => index = i);
                      },
                      itemBuilder: (context, i) => _flowCard(
                        controller: portraitFlowCtrl,
                        games: list,
                        itemIndex: i,
                        coverWidth: coverW,
                        coverHeight: cardH,
                        style: style,
                      ),
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
              duration: _reduceMotion ? Duration.zero : Tokens.fastDur,
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
    final continuing = continuePlaying;
    final recent = recentlyAdded;
    // The two plate sections are enough on their own; a third identical row
    // only appears when the collection is actually being narrowed
    // (a search, a tab, or a system filter), where it earns its place.
    final narrowed =
        query.isNotEmpty || tab != 'all' || filter != 'All systems';
    final hasGlobalHub = continuing.isNotEmpty || recent.isNotEmpty;
    final showNarrowedRow =
        narrowed &&
        (query.isNotEmpty ||
            filter != 'All systems' ||
            (tab != 'all' && tab != 'recent' && tab != 'continue'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(osPad, 12, osPad, 0),
          child: Row(
            children: [
              _search(hint: 'Search games…'),
              const SizedBox(width: 8),
              _importButton(),
            ],
          ),
        ),
        _strip(osPad),
        Expanded(
          child: !hasGlobalHub && games.isEmpty
              ? _empty()
              : ListView(
                  padding: EdgeInsets.fromLTRB(osPad, 8, osPad, 20),
                  children: [
                    if (continuing.isNotEmpty) ...[
                      OrbitSectionHeader(
                        title: 'Continue playing',
                        onSeeAll: () => _setTab('recent'),
                      ),
                      const SizedBox(height: 10),
                      _tileRow(
                        continuing,
                        footnote: (g) => lastPlayedLabel(g.lastPlayedMs),
                      ),
                      const SizedBox(height: 22),
                    ],
                    if (recent.isNotEmpty) ...[
                      OrbitSectionHeader(
                        title: 'Recently added',
                        onSeeAll: () => _clearFilters(),
                      ),
                      const SizedBox(height: 10),
                      // This row is an import-order snapshot, not a second
                      // view of the currently filtered collection.
                      _tileRow(recent, footnote: (g) => _systemNote(g)),
                    ],
                    if (showNarrowedRow && games.isNotEmpty) ...[
                      const SizedBox(height: 22),
                      OrbitSectionHeader(
                        title: switch (tab) {
                          'favorites' => 'Favorites',
                          'recent' => 'Recent',
                          'continue' => 'Continue playing',
                          _ => 'The collection',
                        },
                      ),
                      const SizedBox(height: 10),
                      _tileRow(games, footnote: (g) => _systemNote(g)),
                    ],
                    if (games.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: Text(
                          'No titles match this view.',
                          style: Tokens.body(size: 12, color: Tokens.muted),
                          textAlign: TextAlign.center,
                        ),
                      ),
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
    final controller = _flowControllerFor(Layout.of(context));
    final style = MediaQuery.disableAnimationsOf(context)
        ? CoverFlowStyle.flat
        : _flowStyle;
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
              LayoutBuilder(
                builder: (context, constraints) {
                  // Page pitch follows the viewport while the actual cover
                  // stays inside its slot. That leaves a clean, visible edge
                  // of the neighboring covers on both sides.
                  final slotWidth =
                      constraints.maxWidth * controller.viewportFraction;
                  final cardWidth = math.min(coverW, slotWidth * 0.88);
                  final cardHeight = math.min(coverH, cardWidth / 0.72);
                  return _flowViewport(
                    controller: controller,
                    child: PageView.builder(
                      controller: controller,
                      physics: _flowPhysics,
                      pageSnapping: !_reduceMotion,
                      allowImplicitScrolling: !_reduceMotion,
                      scrollBehavior: const _CoverFlowScrollBehavior(),
                      itemCount: list.length,
                      onPageChanged: (i) {
                        if (i != index) setState(() => index = i);
                      },
                      itemBuilder: (context, i) => _flowCard(
                        controller: controller,
                        games: list,
                        itemIndex: i,
                        coverWidth: cardWidth,
                        coverHeight: cardHeight,
                        style: style,
                        reflection: reflectH > 0,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                left: osPad,
                child: _FlowButton(
                  icon: Icons.chevron_left,
                  tooltip: 'Previous cover',
                  enabled: index > 0,
                  onTap: () => _move(-1),
                ),
              ),
              Positioned(
                right: osPad,
                child: _FlowButton(
                  icon: Icons.chevron_right,
                  tooltip: 'Next cover',
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
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Opacity(
          opacity: enabled ? 1 : 0.3,
          child: Material(
            color: const Color(0xE6111B2A),
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
        ),
      ),
    );
  }
}

class _CoverFlowScrollBehavior extends MaterialScrollBehavior {
  const _CoverFlowScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}
