import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'brand/brand_mark.dart';
import 'services/gamepad.dart';
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
import 'widgets/orbit_chrome.dart';
import 'widgets/orbit_widgets.dart';
import 'widgets/pad_navigator.dart';

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
  void Function()? _cancelPad;

  @override
  void initState() {
    super.initState();
    state = AppState(dirProvider: widget.dirProvider);
    state.addListener(_syncInputMode);
    _cancelPad = GamepadService.shared.onConnection((connected, name) {
      InputMode.shared.notePad(connected ? name : null);
    });
    InputMode.shared.notePad(GamepadService.shared.connectedPad);
    state.load().then((_) {
      _syncInputMode();
      _rescanWatchedFolders();
    });
  }

  /// The persisted "TV mode" setting (and any other input override) is the
  /// single source the modifier layer reads when it resolves a window.
  void _syncInputMode() {
    InputMode.shared.syncFromSettings(state.settings);
  }

  @override
  void dispose() {
    state.removeListener(_syncInputMode);
    _cancelPad?.call();
    super.dispose();
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
      navigatorObservers: [focusRouteObserver],
      // A controller drives every menu (d-pad focus, A select, B back).
      // Esc goes back anywhere; a running game handles Esc itself (its
      // pause menu) before this sees it. The Focus bridge makes arrow keys
      // go through the one focus owner, including its held-repeat timing.
      builder: (context, child) => Focus(
        canRequestFocus: false,
        onKeyEvent: (node, event) => FocusOwner.shared.onKey(event),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                _navigatorKey.currentState?.maybePop(),
          },
          child: PadNavigator(navigatorKey: _navigatorKey, child: child!),
        ),
      ),
      title: 'ezCORE',
      debugShowCheckedModeBanner: false,
      theme: Tokens.theme(),
      home: Listener(
        onPointerHover: (_) => InputMode.shared.notePointer(),
        onPointerDown: (_) => InputMode.shared.notePointer(),
        child: ListenableBuilder(
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
            return ListenableBuilder(
              listenable: InputMode.shared,
              builder: (context, _) => Shell(state: state),
            );
          },
        ),
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
  final _railFocus = FocusNode(debugLabel: 'command rail');

  @override
  void initState() {
    super.initState();
    FocusOwner.shared.attachRail(_railFocus);
  }

  /// Changing destination restores that destination's remembered focus on
  /// the frame after the new page is on screen.
  void _go(String p) {
    setState(() => page = p);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusOwner.shared.setScreen(p);
    });
  }

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
    FocusOwner.shared.detachRail(_railFocus);
    _railFocus.dispose();
    _libraryFilter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final modifier = Layout.modifierOf(context);
    final tv = Layout.isTv(modifier);
    final handheld = Layout.isHandheld(modifier);
    final ultrawide = Layout.isUltrawide(modifier);
    final hasRail = Layout.hasRail(layout);
    final short = Layout.isShort(layout) || handheld;
    final portrait = !hasRail;

    Widget content = SafeArea(
      bottom: hasRail && !tv,
      left: !hasRail,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A TV draws its status bar outside the scaled viewport so the
          // shelf keeps its full desktop height (and its 3D cover flow).
          if ((!short || portrait) && !tv)
            Padding(
              padding: EdgeInsets.fromLTRB(
                portrait ? 16 : 40,
                portrait ? 12 : 22,
                portrait ? 16 : 32,
                0,
              ),
              child: OrbitTopBar(compact: portrait),
            ),
          Expanded(child: _page()),
        ],
      ),
    );
    if (tv) {
      content = Padding(
        padding: EdgeInsets.only(right: Layout.safeArea(modifier)),
        child: content,
      );
    }
    if (ultrawide) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Layout.contentMaxWidth(modifier),
          ),
          child: content,
        ),
      );
    }

    final safe = Layout.safeArea(modifier);
    Widget body = Stack(
      children: [
        Ambient(motion: widget.state.settings['motion'] != false),
        if (hasRail)
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(
                focusNode: _railFocus,
                child: OrbitRail(
                  page: page,
                  onGo: _go,
                  short: short,
                  modifier: modifier,
                  onAddGames: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ImportScreen(state: widget.state),
                    ),
                  ),
                ),
              ),
              Expanded(child: content),
            ],
          )
        else
          Column(
            children: [
              Expanded(child: content),
              OrbitBottomNav(page: page, onGo: _go),
            ],
          ),
      ],
    );
    body = InputAwareViewport(child: body);
    if (tv && page == 'library') {
      body = Stack(
        children: [
          body,
          Positioned(
            left: Layout.railWidth(layout, modifier) + safe,
            top: safe + Tokens.s2,
            child: const BrandLockup(height: 30),
          ),
          Positioned(
            right: safe,
            top: safe + Tokens.s2,
            child: const OrbitStatus(),
          ),
        ],
      );
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () => _go('library'),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _go('cores'),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _go('capsule'),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _go('settings'),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(backgroundColor: Tokens.bg, body: body),
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
