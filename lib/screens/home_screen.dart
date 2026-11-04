import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/collection_view.dart' show libraryViewKey;
import '../widgets/cover_flow.dart';
import '../widgets/focus_glow.dart';
import '../widgets/game_dock.dart';
import '../widgets/library_header.dart';
import '../widgets/orbit_overlays.dart';
import '../widgets/orbit_widgets.dart';
import 'cheats_screen.dart';
import 'game_detail_screen.dart';
import 'import_screen.dart';
import 'launch.dart';

/// Library, the home screen: the collection header, the system chips, one of
/// five looks for the same games, and the selected game's dock (§8.1).
///
/// The default look is the 3D shelf. It opens on the game played last, so
/// Resume is always one press away. Search, filters, sort, the look switch,
/// favourites, details, cheats and removal all stay reachable on every size;
/// the dock and header fold down to one line as the window shrinks.
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

/// Filter ids that are not a system id.
const _favoritesTab = 'favorites';
const _allTab = 'all';

/// The order the design lists system chips in (§8.1): Nintendo handhelds and
/// consoles by generation, then the other platforms.
const _systemChipOrder = <String>[
  'nes',
  'snes',
  'n64',
  'gb',
  'gbc',
  'gba',
  'nds',
  'psx',
  'dc',
  'psp',
  'genesis',
  'saturn',
  'arcade',
  'atari2600',
  'pce',
  'tg16',
  'pcecd',
  'sms',
  'gg',
  'ngc',
];

/// Which shell of the library to draw. Derived from [Layout] plus the height:
/// the 3D shelf needs vertical room, so a short desktop window uses the shelf
/// rows instead (§10).
enum _LibraryShape {
  desktop,
  tablet,
  tabletPortrait,
  phonePortrait,
  phoneLandscape,

  /// A window smaller than a phone: only the title, the games and one action
  /// row. No chrome is worth keeping at 320×192.
  mini,
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'library search');
  String _filter = _allTab; // _allTab, _favoritesTab or a system id
  _Sort _sort = _Sort.recent;
  String? _selectedId;
  bool _phoneSearchOpen = false;
  final _viewChipKey = GlobalKey();

  AppState get state => widget.state;

  LibraryLook get _look =>
      LibraryLook.fromSetting(state.settings[libraryViewKey]);

  void _setLook(LibraryLook look) =>
      state.setSetting(libraryViewKey, look.value);

  @override
  void initState() {
    super.initState();
    // Open on the game played last (§2). An explicit filter or sort later
    // clears it, so the shelf then starts at the first game in view.
    _selectedId = lastPlayed(widget.state.games)?.id;
    widget.filterRequests?.addListener(_applyRequest);
    _search.addListener(_onSearchChanged);
  }

  void _applyRequest() {
    final f = widget.filterRequests?.value;
    if (f != null && mounted) {
      setState(() {
        _filter = f;
        _search.clear();
        _selectedId = null;
      });
    }
  }

  void _onSearchChanged() {
    if (mounted) setState(() => _selectedId = null);
  }

  @override
  void dispose() {
    widget.filterRequests?.removeListener(_applyRequest);
    _search.removeListener(_onSearchChanged);
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

  void _openCheats(GameEntry g) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CheatsScreen(gameId: g.id, state: state),
    ),
  );

  void _play(GameEntry g) =>
      launchGame(context, state, g, resume: g.lastPlayedMs > 0);

  List<GameEntry> _visible() {
    final q = _search.text.trim().toLowerCase();
    final out = state.games.where((g) {
      switch (_filter) {
        case _allTab:
          break;
        case _favoritesTab:
          if (!g.favorite) return false;
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

    out.sort(switch (_sort) {
      _Sort.recent => byPlay,
      _Sort.title => byTitle,
      _Sort.system => (a, b) {
        final c = systemLabel(a.system).compareTo(systemLabel(b.system));
        return c != 0 ? c : byTitle(a, b);
      },
    });
    return out;
  }

  /// The selected game: the one the dock describes.
  GameEntry? _selected(List<GameEntry> visible) {
    if (visible.isEmpty) return null;
    final byId = _selectedId == null
        ? null
        : visible.where((g) => g.id == _selectedId).firstOrNull;
    if (byId != null) return byId;
    // A new filter or sort: start at the first game in the new order.
    return visible.first;
  }

  void _select(GameEntry g) => setState(() => _selectedId = g.id);

  List<LibraryFilterChip> _chips() {
    final games = state.games;
    final counts = <String, int>{};
    for (final g in games) {
      counts[g.system] = (counts[g.system] ?? 0) + 1;
    }
    final systems = counts.keys.toList()
      ..sort((a, b) {
        final ia = _systemChipOrder.indexOf(a);
        final ib = _systemChipOrder.indexOf(b);
        if (ia >= 0 || ib >= 0) {
          if (ia < 0) return 1;
          if (ib < 0) return -1;
          return ia.compareTo(ib);
        }
        return systemLabel(a).compareTo(systemLabel(b));
      });
    return [
      LibraryFilterChip(id: _allTab, label: 'All games', count: games.length),
      LibraryFilterChip(
        id: _favoritesTab,
        label: 'Favorites',
        count: games.where((g) => g.favorite).length,
      ),
      for (final s in systems)
        LibraryFilterChip(id: s, label: systemCode(s), count: counts[s] ?? 0),
    ];
  }

  _LibraryShape _shape(Size screen, double height) {
    // The family comes from the whole window (the shell already chose the
    // rail from it); only the content height decides the short-window and
    // miniature variants.
    final family = Layout.ofSize(
      screen,
      screen.width >= screen.height
          ? Orientation.landscape
          : Orientation.portrait,
    );
    if (height < 300) return _LibraryShape.mini;
    // The 3D shelf needs room for its cover, reflection, header and dock. A
    // short desktop window (1180×820 gives the content 744 px) gets the
    // tablet's shelf rows instead, exactly as device frame 1d shows.
    if (family == OrbitLayout.desktop && height < 800) {
      return _LibraryShape.tablet;
    }
    return switch (family) {
      OrbitLayout.desktop => _LibraryShape.desktop,
      OrbitLayout.tablet => _LibraryShape.tablet,
      OrbitLayout.tabletPortrait => _LibraryShape.tabletPortrait,
      OrbitLayout.phonePortrait => _LibraryShape.phonePortrait,
      OrbitLayout.phoneLandscape => _LibraryShape.phoneLandscape,
    };
  }

  bool get _typing => _searchFocus.hasFocus;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        for (final a in librarySearchActivators)
          a: () => _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyQ): _quickOptions,
        const SingleActivator(LogicalKeyboardKey.keyE): _quickDetails,
        const SingleActivator(LogicalKeyboardKey.keyV): _cycleLook,
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
            _cycleFilter(-1),
        const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
            _cycleFilter(1),
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => LayoutBuilder(
            builder: (context, c) => _body(c.maxWidth, c.maxHeight),
          ),
        ),
      ),
    );
  }

  void _quickOptions() {
    if (_typing) return;
    final selected = _selected(_visible());
    if (selected != null) _openOptions(selected);
  }

  void _quickDetails() {
    if (_typing) return;
    final selected = _selected(_visible());
    if (selected != null) _openDetail(selected);
  }

  void _cycleLook() {
    if (_typing) return;
    _setLook(_look.next);
  }

  void _cycleFilter(int step) {
    if (_typing) return;
    final chips = _chips();
    final at = chips.indexWhere((c) => c.id == _filter);
    final next = ((at < 0 ? 0 : at) + step) % chips.length;
    setState(() {
      _filter = chips[next < 0 ? next + chips.length : next].id;
      _selectedId = null;
    });
  }

  Widget _body(double width, double height) {
    final games = state.games;
    if (games.isEmpty) {
      return CustomScrollView(slivers: [SliverToBoxAdapter(child: _empty())]);
    }
    final shape = _shape(MediaQuery.sizeOf(context), height);
    final visible = _visible();
    final selected = _selected(visible);

    final look = _resolvedLook(shape);
    final chips = _chips();

    if (visible.isEmpty) {
      return _scaffold(
        shape: shape,
        width: width,
        chips: chips,
        selected: selected,
        content: _noMatch(),
      );
    }

    final content = switch (look) {
      LibraryLook.flow => _coverFlow(shape, visible),
      LibraryLook.wall => _wall(shape, visible),
      LibraryLook.shelf => _shelfRows(visible),
      LibraryLook.grid || LibraryLook.list => _collectionPage(shape, visible),
    };

    return _scaffold(
      shape: shape,
      width: width,
      chips: chips,
      selected: selected,
      content: content,
    );
  }

  /// Tablets and phone-sized windows keep the 3D look only when they have the
  /// room for it; otherwise the default (flow) becomes the shelf rows §10 asks
  /// for, exactly as the device frames show.
  LibraryLook _resolvedLook(_LibraryShape shape) {
    final look = _look;
    if (look != LibraryLook.flow) return look;
    return switch (shape) {
      _LibraryShape.tablet || _LibraryShape.tabletPortrait => LibraryLook.shelf,
      _ => look,
    };
  }

  /// The shared frame: title/tools/chips, then the look, then the dock.
  Widget _scaffold({
    required _LibraryShape shape,
    required double width,
    required List<LibraryFilterChip> chips,
    required GameEntry? selected,
    required Widget content,
  }) {
    final desktop = shape == _LibraryShape.desktop;
    final mini = shape == _LibraryShape.mini;
    final phone =
        shape == _LibraryShape.phonePortrait ||
        shape == _LibraryShape.phoneLandscape;
    final pad = mini ? 12.0 : (phone ? 20.0 : 48.0);
    final dockPad = mini
        ? 10.0
        : shape == _LibraryShape.desktop ||
              shape == _LibraryShape.tablet ||
              shape == _LibraryShape.tabletPortrait
        ? 44.0
        : (shape == _LibraryShape.phoneLandscape ? 24.0 : 16.0);
    final top = mini ? 6.0 : (desktop ? 12.0 : 18.0);
    final titleSize = mini
        ? 22.0
        : (phone ? Tokens.screenTitle * 0.85 : Tokens.screenTitle);
    final showEyebrow =
        !mini &&
        (shape == _LibraryShape.desktop ||
            shape == _LibraryShape.tabletPortrait);
    final showChips = !mini && shape != _LibraryShape.phoneLandscape;
    final dockMode = switch (shape) {
      _LibraryShape.desktop => GameDockMode.full,
      _LibraryShape.phonePortrait => GameDockMode.stacked,
      _LibraryShape.mini => GameDockMode.mini,
      _ => GameDockMode.oneLine,
    };
    final bottomSpace = switch (shape) {
      _LibraryShape.phonePortrait => 14.0,
      _LibraryShape.phoneLandscape => 74.0,
      _LibraryShape.mini => 6.0,
      _ => 82.0,
    };
    final gapAfterChips = mini ? 6.0 : (desktop ? 30.0 : 16.0);
    final gapAfterHeader = mini ? 6.0 : (desktop ? 15.0 : 14.0);

    final title = LibraryTitle(
      count: state.games.length,
      titleSize: titleSize,
      countSize: desktop ? 16 : 14,
      showEyebrow: showEyebrow,
      showCount: !mini,
      compactCount: phone,
    );

    final tools = mini
        ? const SizedBox.shrink()
        : desktop
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LibrarySearchField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: (_) {},
                width: 240,
                height: 46,
              ),
              const SizedBox(width: 12),
              LibraryLookSwitch(value: _look, onChanged: _setLook, height: 46),
              const SizedBox(width: 12),
              LibraryViewChip(key: _viewChipKey, onPressed: _openViewMenu),
            ],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundToolButton(
                icon: _phoneSearchOpen ? Symbols.close : Symbols.search,
                tooltip: _phoneSearchOpen ? 'Close search' : 'Search',
                onPressed: () => setState(() {
                  _phoneSearchOpen = !_phoneSearchOpen;
                  if (!_phoneSearchOpen) {
                    _search.clear();
                    _searchFocus.unfocus();
                  } else {
                    _searchFocus.requestFocus();
                  }
                }),
              ),
              if (!phone) ...[
                const SizedBox(width: 8),
                LibraryLookSwitch(
                  value: _look,
                  onChanged: _setLook,
                  height: 40,
                  iconOnly: true,
                ),
              ],
              const SizedBox(width: 8),
              LibraryViewChip(
                key: _viewChipKey,
                onPressed: _openViewMenu,
                size: 40,
              ),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pad, top, pad, 0),
          child: Row(
            crossAxisAlignment: desktop
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              if (desktop)
                Padding(padding: const EdgeInsets.only(top: 4), child: tools)
              else
                tools,
            ],
          ),
        ),
        if (!desktop && _phoneSearchOpen) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 10, pad, 0),
            child: LibrarySearchField(
              controller: _search,
              focusNode: _searchFocus,
              onChanged: (_) {},
              width: double.infinity,
              height: 42,
              autofocus: true,
              showShortcut: false,
            ),
          ),
        ],
        if (showChips) ...[
          SizedBox(height: gapAfterHeader),
          LibraryChips(
            chips: chips,
            selectedId: _filter,
            onSelected: (id) => setState(() {
              _filter = id;
              _selectedId = null;
            }),
            height: desktop ? 38 : (phone ? 32 : 36),
            fontSize: desktop ? 14 : 13,
            padding: EdgeInsets.only(left: phone ? pad : 44, right: 44),
          ),
        ],
        SizedBox(height: gapAfterChips),
        Expanded(child: content),
        if (selected != null) ...[
          SizedBox(height: mini ? 6 : (phone ? 12 : 20)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: dockPad),
            child: GameDock(
              game: selected,
              mode: dockMode,
              height: shape == _LibraryShape.tabletPortrait ? 112 : null,
              showBadgeOnOneLine: shape == _LibraryShape.tabletPortrait,
              onResume: () => _play(selected),
              onDetails: () => _openDetail(selected),
              onFavorite: () => state.toggleFavorite(selected.id),
              onMore: () => _openOptions(selected),
            ),
          ),
        ],
        SizedBox(height: bottomSpace),
      ],
    );
  }

  /// V / the View chip: the five looks and the three sorts in one menu, so
  /// every way of changing the view is reachable with a mouse or a thumb.
  ///
  /// A menu (not a sheet) because it can scroll: on a phone held sideways
  /// eight rows are taller than the screen.
  Future<void> _openViewMenu() async {
    final box = _viewChipKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final value = await showMenu<String>(
      context: context,
      color: Tokens.toastBg,
      position: RelativeRect.fromRect(
        box.localToGlobal(Offset.zero) & box.size,
        Offset.zero & overlay.size,
      ),
      items: [
        for (final look in LibraryLook.values)
          PopupMenuItem(
            value: 'look:${look.value}',
            height: 44,
            child: _MenuRow(
              icon: look.icon,
              label: look.label,
              selected: look == _look,
            ),
          ),
        const PopupMenuDivider(),
        for (final sort in _Sort.values)
          PopupMenuItem(
            value: 'sort:${sort.name}',
            height: 44,
            child: _MenuRow(
              icon: Symbols.tune,
              label: 'Sort: ${sort.label}',
              selected: sort == _sort,
            ),
          ),
      ],
    );
    if (!mounted || value == null) return;
    final parts = value.split(':');
    if (parts.length != 2) return;
    if (parts.first == 'look') {
      _setLook(LibraryLook.fromSetting(parts.last));
    } else {
      setState(() {
        _sort = _Sort.values.firstWhere(
          (s) => s.name == parts.last,
          orElse: () => _Sort.recent,
        );
        _selectedId = null;
      });
    }
  }

  /// Q, long-press or the dock's ⋯: the selected game's options (§9).
  Future<void> _openOptions(GameEntry game) async {
    final played = game.lastPlayedMs > 0;
    final action = await showOrbitOptionsSheet<String>(
      context,
      title: game.title,
      subtitle: '${systemLabel(game.system)} · ${fileSizeLabel(game.fileSize)}',
      items: [
        OrbitSheetItem(
          label: played ? 'Resume' : 'Play',
          icon: Symbols.playArrow,
          value: 'resume',
        ),
        OrbitSheetItem(
          label: 'Details and snapshots',
          icon: Symbols.info,
          value: 'details',
        ),
        OrbitSheetItem(
          label: game.favorite ? 'Remove from favorites' : 'Add to favorites',
          icon: Symbols.favorite,
          value: 'favorite',
        ),
        OrbitSheetItem(label: 'Cheats', icon: Symbols.bolt, value: 'cheats'),
        OrbitSheetItem(
          label: 'Remove from collection',
          icon: Symbols.delete,
          value: 'remove',
          danger: true,
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'resume':
        _play(game);
      case 'details':
        _openDetail(game);
      case 'favorite':
        state.toggleFavorite(game.id);
      case 'cheats':
        _openCheats(game);
      case 'remove':
        await _confirmRemove(game);
    }
  }

  /// Removal is confirmed with the safe choice focused, then offers Undo for
  /// six seconds at the index it left from (§2, §9).
  Future<void> _confirmRemove(GameEntry game) async {
    final ok = await showOrbitConfirmDialog(
      context,
      title: 'Remove ${game.title}?',
      body:
          'This removes the game from your collection. The file on this '
          'device is not touched, so you can add it again at any time.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep it',
    );
    if (!mounted || !ok) return;
    state.removeGame(game.id);
    if (!mounted) return;
    setState(() => _selectedId = null);
    showOrbitToast(
      context,
      message: 'Removed ${game.title}',
      icon: Symbols.delete,
      undoGlyph: 'Y',
      onUndo: () => state.addGame(game),
    );
  }

  /// The 3D shelf: 270×360 covers on a 1500 px perspective, the focused one
  /// forward and its neighbours turned 58° away (§8.1).
  Widget _coverFlow(_LibraryShape shape, List<GameEntry> visible) {
    final selected = _selected(visible);
    final index = selected == null
        ? 0
        : visible
              .indexWhere((g) => g.id == selected.id)
              .clamp(0, visible.length - 1);
    return LayoutBuilder(
      builder: (context, c) {
        final Size size;
        switch (shape) {
          case _LibraryShape.desktop:
            size = const Size(270, 360);
          case _LibraryShape.phonePortrait:
            final w = (c.maxWidth * 0.55).clamp(150.0, 250.0);
            size = Size(w, w / 0.68);
          case _LibraryShape.phoneLandscape:
            final h = (c.maxHeight * 0.72).clamp(120.0, 215.0);
            size = Size(h * 0.75, h);
          case _LibraryShape.tablet:
          case _LibraryShape.tabletPortrait:
            final h = (c.maxHeight * 0.66).clamp(150.0, 300.0);
            size = Size(h * 0.75, h);
          case _LibraryShape.mini:
            final h = (c.maxHeight * 0.80).clamp(40.0, 120.0);
            size = Size(h * 0.75, h);
        }
        return Semantics(
          container: true,
          label: 'Game ${index + 1} of ${visible.length}',
          child: CoverFlow(
            count: visible.length,
            index: index,
            itemSize: size,
            reflection: true,
            autofocus: true,
            semanticLabel: 'Games',
            onIndexChanged: (i) {
              if (i >= 0 && i < visible.length) {
                _select(visible[i]);
              }
            },
            onActivate: (i) => _openDetail(visible[i]),
            itemBuilder: (context, i, front) => GameCover(
              gameId: visible[i].id,
              title: visible[i].title,
              systemId: visible[i].system,
              year: visible[i].year,
              favorite: visible[i].favorite,
              radius: 7,
            ),
          ),
        );
      },
    );
  }

  /// Wall: the same shelf at a flatter angle and poster-sized covers (§8.1).
  Widget _wall(_LibraryShape shape, List<GameEntry> visible) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = (c.maxHeight * 0.74).clamp(150.0, 260.0);
        final size = Size(h * 0.75, h);
        final selected = _selected(visible);
        final index = selected == null
            ? 0
            : visible
                  .indexWhere((g) => g.id == selected.id)
                  .clamp(0, visible.length - 1);
        return CoverFlow(
          count: visible.length,
          index: index,
          itemSize: size,
          frontScale: 1.02,
          angle: 34,
          spread: 0.80,
          reflection: false,
          autofocus: true,
          semanticLabel: 'Games wall',
          onIndexChanged: (i) {
            if (i >= 0 && i < visible.length) _select(visible[i]);
          },
          onActivate: (i) => _openDetail(visible[i]),
          itemBuilder: (context, i, front) => GameCover(
            gameId: visible[i].id,
            title: visible[i].title,
            systemId: visible[i].system,
            year: visible[i].year,
            favorite: visible[i].favorite,
            radius: 7,
          ),
        );
      },
    );
  }

  /// Shelf (§8.1): "Continue playing" wide cards, then a row of tall covers
  /// per family of system.
  Widget _shelfRows(List<GameEntry> visible) {
    final played = [
      for (final g in visible)
        if (g.lastPlayedMs > 0) g,
    ]..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    final continueGames = played.take(4).toList();
    final continueIds = {for (final g in continueGames) g.id};
    final rest = [
      for (final g in visible)
        if (!continueIds.contains(g.id)) g,
    ];
    const handheld = {'gb', 'gbc', 'gba', 'nds', 'psp', 'gg', '3ds', 'switch'};
    final handheldGames = [
      for (final g in rest)
        if (handheld.contains(g.system)) g,
    ];
    final consoleGames = [
      for (final g in rest)
        if (!handheld.contains(g.system)) g,
    ];

    return CustomScrollView(
      slivers: [
        if (continueGames.isNotEmpty) ...[
          _sectionHeader('Continue playing'),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.28,
              ),
              itemCount: continueGames.length,
              itemBuilder: (context, i) => _ContinueCard(
                game: continueGames[i],
                selected: continueGames[i].id == _selectedId,
                onTap: () {
                  _select(continueGames[i]);
                  _play(continueGames[i]);
                },
              ),
            ),
          ),
        ],
        if (handheldGames.isNotEmpty) ...[
          _sectionHeader('Handhelds'),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 168,
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: 0.67,
              ),
              itemCount: handheldGames.length,
              itemBuilder: (context, i) => _ShelfTile(
                game: handheldGames[i],
                selected: handheldGames[i].id == _selectedId,
                onTap: () => _onShelfTap(handheldGames[i]),
              ),
            ),
          ),
        ],
        if (consoleGames.isNotEmpty) ...[
          _sectionHeader('Home consoles'),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 168,
                mainAxisSpacing: 18,
                crossAxisSpacing: 18,
                childAspectRatio: 0.67,
              ),
              itemCount: consoleGames.length,
              itemBuilder: (context, i) => _ShelfTile(
                game: consoleGames[i],
                selected: consoleGames[i].id == _selectedId,
                onTap: () => _onShelfTap(consoleGames[i]),
              ),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  void _onShelfTap(GameEntry g) {
    if (g.id == _selectedId) {
      _play(g);
    } else {
      _select(g);
    }
  }

  Widget _sectionHeader(String title) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(44, 18, 44, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [Text(title, style: Tokens.sectionTitle)],
      ),
    ),
  );

  /// Grid and List: the collection below Resume and Continue, with the same
  /// sections and grouping the library has always had.
  Widget _collectionPage(_LibraryShape shape, List<GameEntry> visible) {
    final compact =
        shape == _LibraryShape.phonePortrait ||
        shape == _LibraryShape.phoneLandscape ||
        shape == _LibraryShape.mini;
    final pad = compact ? 20.0 : 44.0;
    final everything = _filter == _allTab && _search.text.trim().isEmpty;
    final last = everything ? lastPlayed(state.games) : null;
    final recent = [
      if (everything)
        for (final g in state.games)
          if (g.lastPlayedMs > 0 && g.id != last?.id) g,
    ]..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));

    return CustomScrollView(
      slivers: [
        if (last != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
            sliver: SliverToBoxAdapter(
              child: _ResumeCard(
                game: last,
                state: state,
                compact: compact,
                short: shape == _LibraryShape.phoneLandscape,
                onDetails: () => _openDetail(last),
                onPlay: () => _play(last),
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
                    onTap: () => _play(recent[i]),
                    semanticsHint: 'Resume',
                  ),
                ),
              ),
            ),
          ),
        ],
        if (last != null || recent.isNotEmpty)
          _sectionTitle('All games', pad, key: const Key('library-all-games')),
        if (_look == LibraryLook.list) ...[
          if (_grouped)
            for (final (i, group) in _bySystem(visible).indexed) ...[
              _systemHeading(group, pad, first: i == 0),
              _listSliver(group, pad, top: 0),
            ]
          else
            _listSliver(visible, pad),
        ] else if (_grouped)
          for (final (i, group) in _bySystem(visible).indexed) ...[
            _systemHeading(group, pad, first: i == 0),
            _gridSliver(group, compact, pad, top: 0),
          ]
        else
          _gridSliver(visible, compact, pad),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  bool get _grouped =>
      _sort == _Sort.system &&
      {for (final g in state.games) g.system}.length > 1;

  List<List<GameEntry>> _bySystem(List<GameEntry> games) {
    final out = <List<GameEntry>>[];
    for (final g in games) {
      if (out.isEmpty || out.last.first.system != g.system) out.add([]);
      out.last.add(g);
    }
    return out;
  }

  Widget _listSliver(List<GameEntry> games, double pad, {double top = 12}) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, top, pad, 0),
      sliver: SliverList.separated(
        itemCount: games.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _ListRow(
          game: games[i],
          selected: games[i].id == _selectedId,
          onTap: () => _onShelfTap(games[i]),
        ),
      ),
    );
  }

  Widget _gridSliver(
    List<GameEntry> games,
    bool compact,
    double pad, {
    double top = 12,
  }) {
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(pad, top, pad, 0),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: compact ? 130 : 160,
          mainAxisSpacing: 18,
          crossAxisSpacing: compact ? 12 : 18,
          childAspectRatio: 0.60,
        ),
        itemCount: games.length,
        itemBuilder: (context, i) => _Tile(
          game: games[i],
          footnote: shortSystemLabel(games[i].system),
          onTap: () => _onShelfTap(games[i]),
          semanticsHint: 'Open details',
          selected: games[i].id == _selectedId,
        ),
      ),
    );
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

  Widget _sectionTitle(String text, double pad, {Key? key}) => SliverPadding(
    padding: EdgeInsets.fromLTRB(pad, 28, pad, 12),
    sliver: SliverToBoxAdapter(
      child: Text(text, key: key, style: Tokens.sectionTitle),
    ),
  );

  /// Why nothing shows, and what to do about it.
  Widget _noMatch() => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 0),
      child: Text(
        _search.text.trim().isNotEmpty
            ? 'No games match. Try another filter or search.'
            : switch (_filter) {
                _favoritesTab =>
                  'No favorites yet. Tap ♡ on a game to keep it here.',
                _ => 'No games match. Try another filter or search.',
              },
        style: Tokens.body(size: 14, color: Tokens.muted),
      ),
    ),
  );

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Symbols.videogameAsset, size: 44, color: Tokens.muted),
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
              style: Tokens.body(size: 14, color: Tokens.muted, height: 1.6),
            ),
            const SizedBox(height: 20),
            OrbitPrimary(
              label: 'Add games',
              icon: Symbols.add,
              onPressed: _openImport,
            ),
            if (widget.onOpenCores != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: widget.onOpenCores,
                child: Text(
                  'See systems',
                  style: Tokens.body(size: 14, color: Tokens.systemLabelFg),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// One row of the View menu: icon, label, and a check on the current choice.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: selected ? Tokens.text : Tokens.muted),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: Tokens.body(
              size: 13,
              weight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? Tokens.text : Tokens.muted,
              height: null,
            ),
          ),
        ),
        if (selected)
          const Icon(Symbols.check, size: 16, color: Tokens.accentHi),
      ],
    );
  }
}

/// A round icon control for the compact header (search / view).
class _RoundToolButton extends StatelessWidget {
  const _RoundToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x8C060A11),
                border: Border.all(color: const Color(0x2BFFFFFF)),
              ),
              child: Icon(icon, size: 20, color: Tokens.text),
            ),
          ),
        ),
      ),
    );
  }
}

/// Continue playing: a wide card with the game's art and its title on it.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.game,
    required this.selected,
    required this.onTap,
  });

  final GameEntry game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusGlow(
      onTap: onTap,
      radius: 7,
      lift: 1.02,
      semanticLabel: game.title,
      semanticHint: 'Resume',
      child: Stack(
        fit: StackFit.expand,
        children: [
          GameCover(
            gameId: game.id,
            title: game.title,
            systemId: game.system,
            year: game.year,
            favorite: game.favorite,
            radius: 7,
          ),
          if (selected)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: Tokens.accent, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A tall cover on the shelf: the art, its title and the system's code.
class _ShelfTile extends StatelessWidget {
  const _ShelfTile({
    required this.game,
    required this.selected,
    required this.onTap,
  });

  final GameEntry game;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FocusGlow(
      onTap: onTap,
      radius: 7,
      lift: 1.02,
      semanticLabel: game.title,
      semanticHint: 'Open details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                GameCover(
                  gameId: game.id,
                  title: game.title,
                  systemId: game.system,
                  year: game.year,
                  favorite: game.favorite,
                  radius: 7,
                ),
                if (selected)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: Tokens.accent, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            systemLabel(game.system).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Tokens.body(
              size: 11,
              weight: FontWeight.w600,
              color: Tokens.muted,
              height: null,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tap back into the game played last — on any core.
class _ResumeCard extends StatelessWidget {
  const _ResumeCard({
    required this.game,
    required this.state,
    required this.compact,
    required this.short,
    required this.onDetails,
    required this.onPlay,
  });

  final GameEntry game;
  final AppState state;
  final bool compact;
  final bool short;
  final VoidCallback onDetails;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final cover = GameCover(
      gameId: game.id,
      title: game.title,
      systemId: game.system,
      year: game.year,
      favorite: game.favorite,
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
            size: 12,
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
        Text(
          '${systemLabel(game.system)} · ${lastPlayedLabel(game.lastPlayedMs)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Tokens.body(size: 13, color: Tokens.muted),
        ),
      ],
    );
    final resume = OrbitPrimary(
      label: 'Resume',
      expanded: compact,
      minHeight: compact ? 48 : 52,
      onPressed: onPlay,
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
                  title: game.title,
                  systemId: game.system,
                  year: game.year,
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
    this.selected = false,
  });

  final GameEntry game;
  final String footnote;
  final VoidCallback onTap;
  final String semanticsHint;
  final bool selected;

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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GameCover(
                    gameId: game.id,
                    title: game.title,
                    systemId: game.system,
                    year: game.year,
                    favorite: game.favorite,
                  ),
                  if (selected)
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            Tokens.radiusCover,
                          ),
                          border: Border.all(color: Tokens.accent, width: 2),
                        ),
                      ),
                    ),
                ],
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

/// A game as one row: small cover, title, system and when it was played.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.game,
    required this.selected,
    required this.onTap,
  });

  final GameEntry game;
  final bool selected;
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
          color: selected ? const Color(0x14007BFF) : const Color(0x0CDDE6F4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0x80007BFF) : Tokens.line,
          ),
        ),
        child: Row(
          children: [
            GameCover(
              gameId: game.id,
              title: game.title,
              systemId: game.system,
              year: game.year,
              width: 38,
              height: 50,
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
                  Symbols.favorite,
                  size: 16,
                  color: Tokens.systemLabelFg,
                  fill: 1,
                ),
              ),
            const Icon(Symbols.chevronRight, color: Tokens.muted),
          ],
        ),
      ),
    );
  }
}
