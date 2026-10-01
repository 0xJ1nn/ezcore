import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/local_data_dir.dart';
import 'state/app_state.dart';
import 'screens/core_manager_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vault_screen.dart';
import 'theme/layout.dart';
import 'theme/tokens.dart';
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
      builder: (context, child) =>
          PadNavigator(navigatorKey: _navigatorKey, child: child!),
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

/// Three destinations (layout option A): Library (home), Cores, Settings.
/// A rail on wide screens, a bottom bar on phones in portrait; the same
/// three either way. Saves live with their game and in the pause menu, and
/// the full save vault is reachable from Settings.
class _ShellState extends State<Shell> {
  String page = 'library';

  void _go(String p) => setState(() => page = p);

  void _openVault() => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Tokens.bg,
        appBar: AppBar(
          backgroundColor: Tokens.bg,
          title: Text('Saves', style: Tokens.display(size: 18)),
        ),
        body: VaultScreen(state: widget.state),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final layout = Layout.of(context);
    final hasRail = Layout.hasRail(layout);
    final short = Layout.isShort(layout);
    final content = SafeArea(
      bottom: hasRail,
      left: !hasRail,
      child: _page(),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () => _go('library'),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _go('cores'),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _go('settings'),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Tokens.bg,
          body: Stack(
            children: [
              Ambient(motion: widget.state.settings['motion'] != false),
              if (hasRail)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OrbitRail(page: page, onGo: _go, short: short),
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
          ),
        ),
      ),
    );
  }

  Widget _page() {
    final index = switch (page) {
      'cores' => 1,
      'settings' => 2,
      _ => 0,
    };
    return IndexedStack(
      index: index,
      children: [
        HomeScreen(state: widget.state, onOpenCores: () => _go('cores')),
        CoreManagerScreen(
          state: widget.state,
          onBrowseCore: (_) => _go('library'),
        ),
        SettingsScreen(state: widget.state, onGoVault: _openVault),
      ],
    );
  }
}
