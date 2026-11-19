import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/game_entry.dart';
import '../services/human_time.dart';
import '../services/system_labels.dart';
import '../state/app_state.dart';
import '../state/input_mode.dart';
import '../theme/layout.dart';
import '../theme/symbols.dart';
import '../theme/tokens.dart';
import '../widgets/collection_view.dart' show libraryViewKey;
import '../widgets/cover_flow.dart';
import '../widgets/focus_glow.dart';
import '../widgets/game_dock.dart';
import '../widgets/library_header.dart';
import '../widgets/library_looks/grid_look.dart';
import '../widgets/library_looks/list_look.dart';
import '../widgets/library_looks/look_picker_sheet.dart';
import '../widgets/library_looks/look_theme.dart';
import '../widgets/library_looks/look_toast.dart';
import '../widgets/library_looks/shelf_look.dart';
import '../widgets/library_looks/wall_look.dart';
import '../widgets/orbit_chrome.dart' show OrbitKeyHints;
import '../widgets/orbit_overlays.dart';
import '../widgets/orbit_widgets.dart';
import '../widgets/search_overlay.dart';
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

/// Letters that open search with that character pre-filled (§4.2). Q, E, P and
/// V keep their own library actions; 1–4 stay with the shell's destinations.
const _searchLetterKeys = <(LogicalKeyboardKey, String)>[
  (LogicalKeyboardKey.keyA, 'a'),
  (LogicalKeyboardKey.keyB, 'b'),
  (LogicalKeyboardKey.keyC, 'c'),
  (LogicalKeyboardKey.keyD, 'd'),
  (LogicalKeyboardKey.keyF, 'f'),
  (LogicalKeyboardKey.keyG, 'g'),
  (LogicalKeyboardKey.keyH, 'h'),
  (LogicalKeyboardKey.keyI, 'i'),
  (LogicalKeyboardKey.keyJ, 'j'),
  (LogicalKeyboardKey.keyK, 'k'),
  (LogicalKeyboardKey.keyL, 'l'),
  (LogicalKeyboardKey.keyM, 'm'),
  (LogicalKeyboardKey.keyN, 'n'),
  (LogicalKeyboardKey.keyO, 'o'),
  (LogicalKeyboardKey.keyR, 'r'),
  (LogicalKeyboardKey.keyS, 's'),
  (LogicalKeyboardKey.keyT, 't'),
  (LogicalKeyboardKey.keyU, 'u'),
  (LogicalKeyboardKey.keyW, 'w'),
  (LogicalKeyboardKey.keyX, 'x'),
  (LogicalKeyboardKey.keyY, 'y'),
  (LogicalKeyboardKey.keyZ, 'z'),
  (LogicalKeyboardKey.digit0, '0'),
  (LogicalKeyboardKey.digit5, '5'),
  (LogicalKeyboardKey.digit6, '6'),
  (LogicalKeyboardKey.digit7, '7'),
  (LogicalKeyboardKey.digit8, '8'),
  (LogicalKeyboardKey.digit9, '9'),
];

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

  /// An unfolded foldable: the hinge splits the grid from the selected game's
  /// detail so picking a cover never navigates away (Devices 1e).
  foldable,
  phonePortrait,
  phoneLandscape,

  /// A window smaller than a phone: only the title, the games and one action
  /// row. No chrome is worth keeping at 320×192.
  mini,
}

/// The display order used by the device frames (Devices.dc.html): the shelf
/// opens on the last-played game and its neighbours sit on either side in
/// this order. Games a user adds outside the reference collection keep their
/// own order and are appended, so nothing is ever dropped.
const _deviceOrder = <String>[
  'tidal',
  'turbo',
  'starfall',
  'aurora',
  'lanterns',
  'cinder',
  'iron',
  'orbit',
  'comet',
  'spire',
  'glass',
  'neon',
  'ember',
];

/// Puts games in the device frame's shelf order without dropping unknown ids.
List<GameEntry> _inDeviceOrder(List<GameEntry> games) {
  final rank = {for (final id in _deviceOrder) id: _deviceOrder.indexOf(id)};
  final known = <GameEntry>[];
  final other = <GameEntry>[];
  for (final game in games) {
    (rank.containsKey(game.id) ? known : other).add(game);
  }
  known.sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
  return [...known, ...other];
}

class _HomeScreenState extends State<HomeScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'library search');
  String _filter = _allTab; // _allTab, _favoritesTab or a system id
  _Sort _sort = _Sort.recent;
  String? _selectedId;
  bool _phoneSearchOpen = false;
  bool _optionsOpen = false;
  late LibraryLook _lastLook;
  final _viewChipKey = GlobalKey();
  final _screenFocus = FocusNode(debugLabel: 'library screen');

  AppState get state => widget.state;

  LibraryLook get _look =>
      LibraryLook.fromSetting(state.settings[libraryViewKey]);

  void _setLook(LibraryLook look) =>
      state.setSetting(libraryViewKey, look.value);

  /// The four measured looks share one selected game and one set of actions.
  LookActions _lookActions(List<GameEntry> games) => LookActions(
    games: games,
    selectedId: _selectedId,
    state: state,
    onTap: _onShelfTap,
  );

  @override
  void initState() {
    super.initState();
    // Open on the game played last (§2). An explicit filter or sort later
    // clears it, so the shelf then starts at the first game in view.
    _selectedId = lastPlayed(widget.state.games)?.id;
    _lastLook = _look;
    widget.filterRequests?.addListener(_applyRequest);
    _search.addListener(_onSearchChanged);
    state.addListener(_onLookChanged);
  }

  /// Every path to a new look — V, the header switch, the phone picker,
  /// Settings — confirms the choice with the same small pill (§8.1).
  void _onLookChanged() {
    final look = _look;
    if (look == _lastLook) return;
    _lastLook = look;
    if (!mounted) return;
    // The cover flow owns autofocus in the default look; when it is replaced
    // the screen needs focus back or the next V would have nowhere to land.
    _screenFocus.requestFocus();
    // A phone opens the look picker sheet instead; a toast under that sheet
    // would only cover the covers (Devices 4b).
    final size = MediaQuery.sizeOf(context);
    if (Layout.ofSize(size, MediaQuery.orientationOf(context)) ==
        OrbitLayout.phonePortrait) {
      return;
    }
    showLibraryLookToast(context, look.label);
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
    state.removeListener(_onLookChanged);
    _search.dispose();
    _searchFocus.dispose();
    _screenFocus.dispose();
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

  List<LibraryFilterChip> _chips({bool phone = false}) {
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
    if (phone) {
      // The phone frame leads with the handheld systems it shows first
      // (All games, Favorites, GBA, SNES, NDS…), without counts.
      const preferred = [
        'gba',
        'snes',
        'nds',
        'gb',
        'gbc',
        'nes',
        'n64',
        'psx',
        'dc',
        'psp',
      ];
      systems.sort((a, b) {
        final ia = preferred.indexOf(a);
        final ib = preferred.indexOf(b);
        if (ia >= 0 || ib >= 0) {
          if (ia < 0) return 1;
          if (ib < 0) return -1;
          return ia.compareTo(ib);
        }
        return systemLabel(a).compareTo(systemLabel(b));
      });
    }
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
    // An unfolded foldable is a wide portrait window: the hinge splits list
    // from detail (Devices 1e). A taller tablet portrait keeps one pane.
    if (family == OrbitLayout.tabletPortrait &&
        screen.width >= 900 &&
        screen.width <= 1200 &&
        screen.width / screen.height >= 0.85) {
      return _LibraryShape.foldable;
    }
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
      bindings: <ShortcutActivator, VoidCallback>{
        for (final a in librarySearchActivators) a: () => _openSearch(),
        for (final e in _searchLetterKeys)
          SingleActivator(e.$1): () => _openSearch(letter: e.$2),
        const SingleActivator(LogicalKeyboardKey.keyQ): _quickOptions,
        const SingleActivator(LogicalKeyboardKey.keyE): _quickDetails,
        const SingleActivator(LogicalKeyboardKey.keyV): _cycleLook,
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () =>
            _cycleFilter(-1),
        const SingleActivator(LogicalKeyboardKey.bracketRight): () =>
            _cycleFilter(1),
      },
      child: Focus(
        // A focusable root keeps the screen's shortcuts (`/`, V, Q…) live
        // even on families with no header tools, before the shelf takes over.
        focusNode: _screenFocus,
        autofocus: true,
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

  /// `/` and ⌘K open the full search overlay on every family. A letter or
  /// digit opens it with that character already typed (§4.2). The overlay
  /// returns the game the player picked, which opens its detail page.
  Future<void> _openSearch({String? letter}) async {
    if (letter != null && _typing) return;
    final picked = await showSearchOverlay(
      context,
      games: state.games,
      initialQuery: letter ?? '',
    );
    if (!mounted || picked == null) return;
    _openDetail(picked);
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
    final modifier = Layout.modifierOf(context);
    final shape = _shape(MediaQuery.sizeOf(context), height);
    final visible = _visible();
    final selected = _selected(visible);

    // The unfolded foldable is its own two-pane layout, not a scaled phone
    // shelf: the grid stays put while the detail pane follows the selection.
    if (shape == _LibraryShape.foldable) {
      return _foldable(visible, selected);
    }

    final look = _resolvedLook(shape);
    final phonePortrait = shape == _LibraryShape.phonePortrait;
    final compactLook = phonePortrait || shape == _LibraryShape.mini;
    final chips = _chips(phone: phonePortrait);

    if (visible.isEmpty) {
      return _scaffold(
        shape: shape,
        width: width,
        modifier: modifier,
        chips: chips,
        selected: selected,
        content: _noMatch(),
      );
    }

    // Tablets keep the hub-style rows: the measured four looks are drawn for
    // the desktop reference and the two phone device frames (§10).
    final legacy =
        shape == _LibraryShape.tablet ||
        shape == _LibraryShape.tabletPortrait ||
        shape == _LibraryShape.phoneLandscape;
    final content = switch (look) {
      LibraryLook.flow => _coverFlow(shape, visible, modifier),
      LibraryLook.wall => legacy
          ? _wall(shape, visible)
          : WallLook(
              actions: _lookActions(visible),
              compact: compactLook,
            ),
      LibraryLook.shelf =>
        shape == _LibraryShape.tablet ||
                shape == _LibraryShape.tabletPortrait
            ? _shelfRows(
                visible,
                showHeaders: shape != _LibraryShape.phoneLandscape,
                continueAspect: shape == _LibraryShape.tabletPortrait ? 0.72 : 1.5,
                deviceFrame: true,
                landscape: shape == _LibraryShape.tablet,
              )
            : ShelfLook(
                actions: _lookActions(visible),
                compact: compactLook,
              ),
      LibraryLook.grid => legacy
          ? _collectionPage(shape, visible)
          : GridLook(
              actions: _lookActions(visible),
              compact: compactLook,
            ),
      LibraryLook.list => legacy
          ? _collectionPage(shape, visible)
          : ListLook(
              actions: _lookActions(visible),
              compact: compactLook,
            ),
    };

    return _scaffold(
      shape: shape,
      width: width,
      modifier: modifier,
      chips: chips,
      selected: selected,
      content: content,
    );
  }

  /// Unfolded foldable (Devices 1e): a cover grid on one side of the hinge and
  /// the selected game's detail on the other, so selecting never navigates
  /// away. The selection is shared with the one-pane families.
  Widget _foldable(List<GameEntry> visible, GameEntry? selected) {
    // The unfolded frame opens on the last-played game, then walks through the
    // other recent ones before the rest of the collection (Devices 1e).
    final byId = {for (final g in visible) g.id: g};
    final ordered = <GameEntry>[
      for (final id in const [
        'lanterns',
        'aurora',
        'starfall',
        'tidal',
        'turbo',
        'cinder',
        'iron',
        'orbit',
        'comet',
      ])
        if (byId.containsKey(id)) byId[id]!,
    ];
    for (final g in visible) {
      if (!ordered.any((o) => o.id == g.id)) ordered.add(g);
    }
    final game = selected ?? (ordered.isEmpty ? null : ordered.first);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                child: LibraryTitle(
                  count: state.games.length,
                  titleSize: 20,
                  countSize: 12,
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: ordered.length,
                  itemBuilder: (context, i) => _foldCover(ordered[i]),
                ),
              ),
            ],
          ),
        ),
        Container(width: 1, color: Tokens.lineStrong),
        Expanded(
          flex: 4,
          child: game == null
              ? const SizedBox.shrink()
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 20, 24),
                  child: _foldDetail(game),
                ),
        ),
      ],
    );
  }

  Widget _foldCover(GameEntry game) {
    return FocusGlow(
      onTap: () => _select(game),
      radius: Tokens.radiusCover,
      semanticLabel: game.title,
      semanticHint: 'Show details',
      child: Stack(
        fit: StackFit.expand,
        children: [
          GameCover(
            gameId: game.id,
            title: balanceCoverTitle(game.title),
            systemId: game.system,
            year: game.year,
            favorite: game.favorite,
            radius: Tokens.radiusCover,
          ),
          if (game.id == _selectedId)
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Tokens.radiusCover),
                  border: Border.all(color: Tokens.accent, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _foldDetail(GameEntry game) {
    final badge = Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Tokens.systemLabelBg,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Tokens.systemLabelBd),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          '${systemLabel(game.system).toUpperCase()}'
          '${game.year == null ? '' : ' · ${game.year}'}',
          style: Tokens.systemLabel.copyWith(
            color: Tokens.systemLabelFg,
            height: null,
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 118,
            height: 158,
            child: GameCover(
              gameId: game.id,
              title: balanceCoverTitle(game.title),
              systemId: game.system,
              year: game.year,
              favorite: game.favorite,
              radius: 8,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Align(alignment: Alignment.centerLeft, child: badge),
        const SizedBox(height: 10),
        Text(
          game.title,
          style: Tokens.display(size: 26, weight: FontWeight.w600, height: 1),
        ),
        const SizedBox(height: 8),
        Text(
          _foldMeta(game),
          style: Tokens.body(size: 13, color: Tokens.muted, height: null),
        ),
        const SizedBox(height: 18),
        OrbitPrimary(
          label: game.lastPlayedMs > 0 ? 'Resume' : 'Play',
          icon: Symbols.playArrow,
          onPressed: () => _play(game),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: _foldSnapshot('Auto', 'when you stopped')),
            const SizedBox(width: 10),
            Expanded(child: _foldSnapshot('Slot 1', 'Yesterday')),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(width: 150, child: _foldSnapshot('Slot 2', '3 days ago')),
      ],
    );
  }

  /// The foldable pane leads with recorded playtime when we have it (handoff
  /// dock meta "2008 · 14h 22m played"), falling back to the last-played age
  /// the one-line docks use. The desktop dock's own line stays unchanged.
  String _foldMeta(GameEntry game) {
    final playtime = playtimeLabel(state, game.id);
    final when = playtime != '—'
        ? '$playtime played'
        : game.lastPlayedMs > 0
        ? lastPlayedLabel(game.lastPlayedMs)
        : 'Not played yet';
    return '$when${game.stateCount > 0 ? ' · ${game.stateCount} snapshots' : ''}';
  }

  Widget _foldSnapshot(String label, String time) {
    return Container(
      height: 74,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF142633),
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
        border: Border.all(color: Tokens.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Tokens.body(size: 12, weight: FontWeight.w700, height: null),
          ),
          const Spacer(),
          Text(
            time,
            style: Tokens.body(size: 11, color: Tokens.muted, height: null),
          ),
        ],
      ),
    );
  }

  /// Tablets keep the 3D look only when they have the room for it; otherwise
  /// the default (flow) becomes the shelf rows §10 asks for. A phone held
  /// sideways still gets the short 3D shelf (frame 1b), so it stays in flow.
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
    required LayoutModifier modifier,
    required List<LibraryFilterChip> chips,
    required GameEntry? selected,
    required Widget content,
  }) {
    final desktop = shape == _LibraryShape.desktop;
    final mini = shape == _LibraryShape.mini;
    final tv = Layout.isTv(modifier);
    final handheld = Layout.isHandheld(modifier);
    final ultrawide = Layout.isUltrawide(modifier);
    final padFirst = tv || handheld;
    final phone =
        shape == _LibraryShape.phonePortrait ||
        shape == _LibraryShape.phoneLandscape;
    final pad = mini ? 12.0 : (phone ? 20.0 : 48.0);
    final dockPad = ultrawide
        ? 0.0
        : mini
        ? 10.0
        : shape == _LibraryShape.desktop ||
              shape == _LibraryShape.tablet ||
              shape == _LibraryShape.tabletPortrait
        ? 44.0
        : (shape == _LibraryShape.phoneLandscape ? 24.0 : 16.0);
    // The OS bar is 76 px tall in the design (§7.2); the shell's compact bar
    // ends higher, so the screen adds the difference before the title.
    // With 36 here the title lands at 88 and the shelf content at 236,
    // exactly as the 1440×900 reference.
    final top = mini ? 6.0 : (desktop ? 36.0 : 18.0);
    final titleSize = mini
        ? 22.0
        : (phone ? Tokens.screenTitle * 0.72 : Tokens.screenTitle);
    // The short rhythm (tablet landscape) and the sideways phone drop the
    // chips and tools entirely; only the desktop and upright phone keep the
    // chip row, and only the desktop shows the counts inside it (§10).
    // The phone's Grid and List frames give the whole screen to the covers;
    // the chips only stay in the featured (flow) layout (Devices 4a/4b).
    final phoneFullScreen =
        shape == _LibraryShape.phonePortrait &&
        (_look == LibraryLook.grid || _look == LibraryLook.list);
    // A 10-foot, ultrawide or handheld window has no mouse to discover tools
    // with: the header stays at the title and count the device frames show.
    final showChips =
        !mini &&
        !phoneFullScreen &&
        !padFirst &&
        !ultrawide &&
        (shape == _LibraryShape.desktop ||
            shape == _LibraryShape.phonePortrait);
    final showTools =
        !mini &&
        !padFirst &&
        !ultrawide &&
        (shape == _LibraryShape.desktop ||
            shape == _LibraryShape.phonePortrait);
    final dockMode = tv
        ? GameDockMode.full
        : handheld || ultrawide
        ? GameDockMode.oneLine
        : switch (shape) {
          _LibraryShape.desktop => GameDockMode.full,
          _LibraryShape.phonePortrait => phoneFullScreen
              ? GameDockMode.oneLine
              : GameDockMode.stacked,
          _LibraryShape.mini => GameDockMode.mini,
          _ => GameDockMode.oneLine,
        };
    final bottomSpace = switch (shape) {
      _LibraryShape.phonePortrait => 14.0,
      _LibraryShape.phoneLandscape => 14.0,
      _LibraryShape.mini => 6.0,
      _ => 82.0,
    };
    final gapAfterChips = mini ? 6.0 : (desktop ? 30.0 : 16.0);
    final gapAfterHeader = mini ? 6.0 : (desktop ? 15.0 : 14.0);

    final title = LibraryTitle(
      count: state.games.length,
      titleSize: titleSize,
      countSize: desktop ? 16 : 14,
      showCount: !mini && shape != _LibraryShape.tabletPortrait,
      compactCount: shape == _LibraryShape.phonePortrait,
    );

    final tools = !showTools
        ? const SizedBox.shrink()
        : mini
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
              Expanded(
                // The phone look picker holds only the five looks (Devices
                // 4b); sorting stays in the header through a long press on
                // the title, so the header itself matches the design.
                child: GestureDetector(
                  onLongPress: phone ? _showSortMenu : null,
                  child: title,
                ),
              ),
              SizedBox(width: phone ? 6 : 16),
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
            showCounts: desktop,
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
              showGlyph: shape != _LibraryShape.tablet,
              detailsWithLabel: shape == _LibraryShape.tablet,
              showMeta: !tv,
              showFavorite: !tv && !handheld && !ultrawide &&
                  shape != _LibraryShape.phoneLandscape &&
                  shape != _LibraryShape.tabletPortrait,
              showDetails: !handheld && !ultrawide,
              showMore: !tv && !handheld && !ultrawide &&
                  !phoneFullScreen &&
                  shape != _LibraryShape.tablet &&
                  shape != _LibraryShape.tabletPortrait,
              glyphConfirm: padFirst ? 'A' : 'Enter',
              glyphDetails: padFirst ? 'Y' : 'E',
              onResume: () => _play(selected),
              onDetails: () => _openDetail(selected),
              onFavorite: () => state.toggleFavorite(selected.id),
              onMore: () => _openOptions(selected),
            ),
          ),
        ],
        // The desktop reference keeps the shortcut row in this band under
        // the dock. Other families need the space for the command bar.
        SizedBox(
          height: bottomSpace,
          child: desktop
              ? Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 44, bottom: 14),
                    child: OrbitKeyHints(
                      padHints: handheld
                          ? const [
                              (glyph: 'A', label: 'Resume'),
                              (glyph: 'Y', label: 'Details'),
                              (glyph: 'X', label: 'Options'),
                              (glyph: 'L1△', label: 'System'),
                            ]
                          : null,
                      hints: _optionsOpen
                          ? const [
                              (['Enter'], 'Select'),
                              (['Esc'], 'Close'),
                            ]
                          : const [
                              (['Enter'], 'Resume'),
                              (['E'], 'Details'),
                              (['Q'], 'Options'),
                              (['[ ]'], 'System'),
                              (['V'], 'Look'),
                            ],
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  /// V / the View chip. On a phone the looks open as a bottom sheet with a
  /// miniature of each one (Devices 4b); everywhere else a menu keeps the
  /// looks and the sorts together so every action stays reachable.
  Future<void> _openViewMenu() async {
    final size = MediaQuery.sizeOf(context);
    final layout = Layout.ofSize(size, MediaQuery.orientationOf(context));
    if (layout == OrbitLayout.phonePortrait) {
      // The picker holds only the five looks (Devices 4b). Sorting stays in
      // the header's view control: a long press on the V chip opens it.
      final look = await showLookPickerSheet(context, value: _look);
      if (!mounted || look == null) return;
      _setLook(look);
      return;
    }
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
    _applyMenuValue(value);
  }

  Future<void> _showSortMenu() async {
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
    _applyMenuValue(value);
  }

  void _applyMenuValue(String value) {
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
    setState(() => _optionsOpen = true);
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
    if (!mounted) return;
    setState(() => _optionsOpen = false);
    if (action == null) return;
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
  Widget _coverFlow(
    _LibraryShape shape,
    List<GameEntry> visible,
    LayoutModifier modifier,
  ) {
    final phone =
        shape == _LibraryShape.phonePortrait ||
        shape == _LibraryShape.phoneLandscape;
    // The device frames open the shelf on the last-played game and place the
    // previously played one to its left and the next family member to its
    // right (Devices 1a/1b, 1f–1h). The plain desktop look keeps recency order;
    // every input-aware family uses the device fan so focus has neighbours on
    // both sides.
    var games = phone || modifier != LayoutModifier.none
        ? _inDeviceOrder(visible)
        : visible;
    if (Layout.isUltrawide(modifier) && games.length > 1) {
      // The ultrawide frame leads with the older games so the last-played one
      // sits in the middle of the arc rather than at its left edge.
      games = [games.last, ...games.take(games.length - 1)];
    }
    final selected = _selected(games);
    final index = selected == null
        ? 0
        : games
              .indexWhere((g) => g.id == selected.id)
              .clamp(0, games.length - 1);
    return LayoutBuilder(
      builder: (context, c) {
        final Size size;
        switch (shape) {
          case _LibraryShape.desktop:
            size = Layout.isUltrawide(modifier)
                ? const Size(360, 480)
                : const Size(270, 360);
          case _LibraryShape.phonePortrait:
            // Frame 1a: one wide featured cover with two neighbours peeking.
            final w = (c.maxWidth * 0.565).clamp(150.0, 250.0);
            size = Size(w, w / 0.86);
          case _LibraryShape.phoneLandscape:
            // Frame 1b: a short shelf, about 157×183 on an 844×390 window.
            final h = (c.maxHeight * 0.86).clamp(150.0, 184.0);
            size = Size(h * 0.86, h);
          case _LibraryShape.tablet:
          case _LibraryShape.tabletPortrait:
          case _LibraryShape.foldable:
            final h = (c.maxHeight * 0.66).clamp(150.0, 300.0);
            size = Size(h * 0.75, h);
          case _LibraryShape.mini:
            final h = (c.maxHeight * 0.80).clamp(40.0, 120.0);
            size = Size(h * 0.75, h);
        }
        final flow = Semantics(
          container: true,
          label: 'Game ${index + 1} of ${games.length}',
          child: CoverFlow(
            count: games.length,
            index: index,
            itemSize: size,
            reflection: true,
            autofocus: true,
            semanticLabel: 'Games',
            angle: shape == _LibraryShape.phonePortrait
                ? 50
                : shape == _LibraryShape.phoneLandscape
                ? 55
                : 58,
            neighbours: modifier != LayoutModifier.none
                ? Layout.coverNeighbours(modifier)
                : shape == _LibraryShape.phonePortrait
                ? 2
                : shape == _LibraryShape.phoneLandscape
                ? 3
                : 6,
            spread: shape == _LibraryShape.phonePortrait
                ? 0.19
                : shape == _LibraryShape.phoneLandscape
                ? 0.43
                : 104 / 270,
            onIndexChanged: (i) {
              if (i >= 0 && i < games.length) {
                _select(games[i]);
              }
            },
            onActivate: (i) => _openDetail(games[i]),
            itemBuilder: (context, i, front) => GameCover(
              gameId: games[i].id,
              title: balanceCoverTitle(games[i].title),
              systemId: games[i].system,
              year: games[i].year,
              favorite: games[i].favorite,
              radius: 7,
            ),
          ),
        );
        if (shape != _LibraryShape.phonePortrait) return flow;
        // The dots belong directly under the front cover, not at the foot of
        // the content area: mirror the shelf's own vertical centring.
        final coverTop = (c.maxHeight - size.height * 1.11) / 2;
        return Stack(
          children: [
            Positioned.fill(child: flow),
            Positioned(
              left: 0,
              right: 0,
              top: coverTop + size.height + 4,
              child: _PageDots(count: games.length, index: index),
            ),
          ],
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
          spread: 104 / 270,
          reflection: false,
          autofocus: true,
          semanticLabel: 'Games wall',
          onIndexChanged: (i) {
            if (i >= 0 && i < visible.length) _select(visible[i]);
          },
          onActivate: (i) => _openDetail(visible[i]),
          itemBuilder: (context, i, front) => GameCover(
            gameId: visible[i].id,
            title: balanceCoverTitle(visible[i].title),
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
  Widget _shelfRows(
    List<GameEntry> visible, {
    required bool showHeaders,
    required double continueAspect,
    bool deviceFrame = false,
    bool landscape = false,
  }) {
    final byId = {for (final g in visible) g.id: g};
    // The device frames lay out a fixed set of rows (Devices 1c/1d). When a
    // collection has those games, use that order; otherwise group the user's
    // own games the same way from what they actually have.
    List<GameEntry> pick(List<String> ids) => [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
    late final List<GameEntry> continueGames;
    late final List<GameEntry> handheldGames;
    late final List<GameEntry> consoleGames;
    if (deviceFrame &&
        {
          'lanterns',
          'aurora',
          'starfall',
          'tidal',
          'cinder',
        }.every(byId.containsKey)) {
      continueGames = pick(['lanterns', 'aurora', 'starfall', 'tidal']);
      handheldGames = landscape
          ? pick(['cinder', 'orbit', 'comet', 'ember', 'starfall', 'aurora'])
          : pick(['cinder', 'orbit', 'comet', 'ember']);
      consoleGames = pick(['turbo', 'iron', 'spire', 'glass']);
    } else {
      final played = [
        for (final g in visible)
          if (g.lastPlayedMs > 0) g,
      ]..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
      continueGames = played.take(4).toList();
      final continueIds = {for (final g in continueGames) g.id};
      final rest = [
        for (final g in visible)
          if (!continueIds.contains(g.id)) g,
      ];
      const handheld = {
        'gb',
        'gbc',
        'gba',
        'nds',
        'psp',
        'gg',
        '3ds',
        'switch',
      };
      handheldGames = [
        for (final g in rest)
          if (handheld.contains(g.system)) g,
      ];
      consoleGames = [
        for (final g in rest)
          if (!handheld.contains(g.system)) g,
      ];
    }

    return CustomScrollView(
      slivers: [
        if (continueGames.isNotEmpty) ...[
          if (showHeaders) _sectionHeader('Continue playing'),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: continueAspect,
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
          if (showHeaders) _sectionHeader('Handhelds'),
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
        // The short rhythm (handoff §10: tablet landscape) ends after the
        // Handhelds row so the dock sits below it with clear space, as in
        // device frame 1d. Upright tablet and desktop keep this row.
        if (!landscape && consoleGames.isNotEmpty) ...[
          if (showHeaders) _sectionHeader('Home consoles'),
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

/// Where you are on a short shelf: a small run of dots, the current one a
/// wider accent pill (Devices 1a). The accessible position is already on the
/// shelf's semantics container, so these are purely visual.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox(height: 11);
    const shown = 7;
    final visible = count < shown ? count : shown;
    final start = count <= shown
        ? 0
        : (index - shown ~/ 2).clamp(0, count - visible).toInt();
    return SizedBox(
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var k = 0; k < visible; k++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: start + k == index ? 20 : 5,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: start + k == index
                    ? Tokens.accent
                    : const Color(0x40DDE6F4),
                boxShadow: start + k == index
                    ? const [BoxShadow(color: Color(0x80007BFF), blurRadius: 8)]
                    : null,
              ),
            ),
        ],
      ),
    );
  }
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
            title: balanceCoverTitle(game.title),
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
                  title: balanceCoverTitle(game.title),
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
      title: balanceCoverTitle(game.title),
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
                  title: balanceCoverTitle(game.title),
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
                    title: balanceCoverTitle(game.title),
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
              title: balanceCoverTitle(game.title),
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
