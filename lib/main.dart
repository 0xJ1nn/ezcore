import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/game_entry.dart';
import 'services/local_data_dir.dart';
import 'state/app_state.dart';
import 'state/input_mode.dart';
import 'screens/core_manager_screen.dart';
import 'screens/home_screen.dart';
import 'screens/import_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vault_screen.dart';
import 'theme/layout.dart';
import 'theme/tokens.dart';
import 'widgets/fade_indexed_stack.dart';
import 'widgets/hint_row.dart';
import 'widgets/orbit_chrome.dart';
import 'widgets/pad_navigator.dart';
import 'widgets/space_backdrop.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pins the mobile app-support dir before anything resolves paths.
  final dirProvider = await PlatformLocalDataDirProvider.resolve();
  runApp(EmuApp(dirProvider: dirProvider));
}

/// ezCORE — Orbit console shell (final-01).
/// Five layout families: desktop, tablet landscape/portrait, and phone
/// landscape/portrait. All but phone portrait use the command rail; phone
/// portrait uses the bottom command bar.
class EmuApp extends StatefulWidget {
  const EmuApp({super.key, required this.dirProvider});
  final LocalDataDirProvider dirProvider;

  @override
  State<EmuApp> createState() => _EmuAppState();
}

class _EmuAppState extends State<EmuApp> {
  late final AppState state;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    state = AppState(dirProvider: widget.dirProvider);
    state.load().then((_) => _rescanWatchedFolders());
  }

  /// Issue #14: after startup load, best-effort rescan of watched ROM
  /// folders — new files appear in the library without manual import.
  Future<void> _rescanWatchedFolders() async {
    try {
      await state.rescanRomFolders();
    } catch (_) {
      // Startup rescan is best-effort; per-folder failures stay isolated.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      // A controller drives every menu (d-pad focus, A select, B back).
      // Esc goes back anywhere; a running game handles Esc itself (its
      // pause menu) before this sees it.
      builder: (context, child) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _navigatorKey.currentState?.maybePop(),
        },
        child: PadNavigator(navigatorKey: _navigatorKey, child: child!),
      ),
      title: 'ezCORE',
      debugShowCheckedModeBanner: false,
      theme: Tokens.theme(),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.loaded) {
            return const Scaffold(
              backgroundColor: Tokens.bg,
              body: Center(
                child: CircularProgressIndicator(color: Tokens.accent),
              ),
            );
          }
          if (state.loadError != null && kReleaseMode == false) {
            if (state.registry.catalog.isEmpty) {
              return Scaffold(
                backgroundColor: Tokens.bg,
                body: Center(
                  child: Padding(
                    padding: EdgeInsets.all(Tokens.pad),
                    child: Text(
                      'Core catalog failed to load:\n${state.loadError}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              );
            }
          }
          return Shell(state: state);
        },
      ),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key, required this.state});
  final AppState state;

  @override
  State<Shell> createState() => _ShellState();
}

/// The OS: four spaces — Library (home), Systems (cores), Capsule (every
/// save) and Settings — under one top bar (the ezCORE lockup and a status
/// corner). A rail on wide screens, a bottom bar on phones in portrait; keys
/// 1–4 switch space, Esc goes back.
class _ShellState extends State<Shell> {
  String page = 'library';
  final _libraryFilter = ValueNotifier<String?>(null);

  /// One owner for "what did you touch last"; the OS bar and hint row read
  /// the same value, so their glyphs can never disagree.
  final _input = InputModeController();

  void _go(String p) => setState(() => page = p);

  void _openImport() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ImportScreen(state: widget.state)));

  /// Cores → Show games: the library filtered to that core's system (the
  /// first of its systems that has games, else its first system).
  void _browseCore(String coreId) {
    final core = widget.state.registry.catalog
        .where((m) => m.id == coreId)
        .firstOrNull;
    if (core == null) return _go('library');
    final withGames = core.systems.where(
      (s) => widget.state.games.any((g) => g.system == s),
    );
    _libraryFilter.value = null; // a repeat request must still notify
    _libraryFilter.value = withGames.isNotEmpty
        ? withGames.first
        : core.systems.first;
    _go('library');
  }

  @override
  void dispose() {
    _libraryFilter.dispose();
    _input.dispose();
    super.dispose();
  }

  /// The selected game; the latest played stands in for the selection on
  /// every destination.
  GameEntry? get _selectedGame {
    final games = widget.state.games;
    if (games.isEmpty) return null;
    return games.reduce((a, b) => a.lastPlayedMs >= b.lastPlayedMs ? a : b);
  }

  String? get _ambientSystem => _selectedGame?.system;

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final hasRail = Layout.hasRail(layout);
    final portrait = layout == OrbitLayout.phonePortrait;
    final phone = Layout.isPhone(layout);
    // Short landscape (a phone on its side) gives the OS bar's room to the
    // game shelf; every other family keeps the 76 px bar.
    final showTopBar = layout != OrbitLayout.phoneLandscape;
    final bottomBar = Layout.hasBottomBar(layout);
    final planetTop = page == 'library' ? 730.0 : 800.0;
    final cardPadding = portrait ? 16.0 : (phone ? 24.0 : 48.0);

    final content = SafeArea(
      bottom: hasRail,
      left: !hasRail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTopBar)
            Padding(
              padding: EdgeInsets.fromLTRB(cardPadding, 0, phone ? 16 : 44, 0),
              child: OrbitTopBar(compact: phone, input: _input),
            ),
          Expanded(child: _page()),
        ],
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () => _go('library'),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _go('cores'),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _go('capsule'),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _go('settings'),
      },
      child: Focus(
        autofocus: true,
        child: InputModeDetector(
          mode: _input,
          child: Scaffold(
            backgroundColor: Tokens.bg,
            body: Stack(
              children: [
                Positioned.fill(
                  child: SpaceBackdrop(
                    motion: widget.state.settings['motion'] != false,
                    planetTop: planetTop,
                    tint: systemTint(_ambientSystem ?? ''),
                  ),
                ),
                if (hasRail)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OrbitCommandRail(
                        page: page,
                        onGo: _go,
                        onAddGames: _openImport,
                        short: layout == OrbitLayout.phoneLandscape,
                      ),
                      Expanded(child: content),
                    ],
                  )
                else
                  Column(
                    children: [
                      Expanded(child: content),
                      OrbitCommandBar(
                        page: page,
                        onGo: _go,
                        onAddGames: _openImport,
                      ),
                    ],
                  ),
                // Touch-first phone portrait has no keys to hint at.
                if (!bottomBar)
                  Positioned(
                    right: phone ? 16 : 44,
                    bottom: 0,
                    child: IgnorePointer(
                      child: ListenableBuilder(
                        listenable: _input,
                        builder: (context, _) => HintRow(
                          hints: hintsForPage(
                            page,
                            _input.glyphs,
                            libraryConfirm: (_selectedGame?.stateCount ?? 0) > 0
                                ? 'Resume'
                                : 'Play',
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _page() {
    final index = switch (page) {
      'cores' => 1,
      'capsule' => 2,
      'settings' => 3,
      _ => 0,
    };
    return FadeIndexedStack(
      index: index,
      children: [
        HomeScreen(
          state: widget.state,
          onOpenCores: () => _go('cores'),
          filterRequests: _libraryFilter,
        ),
        CoreManagerScreen(state: widget.state, onBrowseCore: _browseCore),
        VaultScreen(state: widget.state),
        SettingsScreen(state: widget.state),
      ],
    );
  }
}
