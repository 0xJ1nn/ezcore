import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/local_data_dir.dart';
import 'state/app_state.dart';
import 'screens/core_manager_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vault_screen.dart';
import 'theme/layout.dart';
import 'theme/tokens.dart';
import 'widgets/orbit_widgets.dart';

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

class _ShellState extends State<Shell> {
  String page = 'library';
  String? libraryFilter;

  void _go(String p) {
    if (p == 'continue' || p == 'favorites') {
      _filterLibrary(p == 'continue' ? 'Continue' : 'Favorites');
      return;
    }
    if (p == 'library') {
      _filterLibrary(null);
      return;
    }
    setState(() => page = p);
  }

  String get _activeRailPage {
    if (page != 'library') return page;
    return switch (libraryFilter) {
      'Continue' => 'continue',
      'Favorites' => 'favorites',
      _ => 'library',
    };
  }

  /// Sends the library to a filter (a core, or a system from the picker)
  /// and brings the Library space forward.
  void _filterLibrary(String? filter) {
    setState(() {
      libraryFilter = filter;
      page = 'library';
    });
  }

  void _onLibraryFilterChanged(String? filter) {
    if (libraryFilter == filter) return;
    setState(() => libraryFilter = filter);
  }

  void _browseCore(String coreId) => _filterLibrary('core:$coreId');

  /// Per-system game counts, for the "Select system" sheet.
  Map<String, int> _systemCounts() {
    final out = <String, int>{};
    for (final g in widget.state.games) {
      out[g.system] = (out[g.system] ?? 0) + 1;
    }
    return out;
  }

  Future<void> _openSystemPicker() async {
    final selected = libraryFilter;
    if (selected != null && selected.startsWith('core:')) return;
    await showSystemPicker(
      context,
      counts: _systemCounts(),
      selected: selected ?? 'All systems',
      favoriteCount: widget.state.games.where((g) => g.favorite).length,
      onPick: _filterLibrary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final layout = Layout.of(context);
    final short = Layout.isShort(layout);
    final osPad = Tokens.osPad(
      size.width,
      portrait: Layout.isPortrait(layout),
      short_: short,
    );
    final hasRail = Layout.hasRail(layout);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.digit1): () => _go('library'),
        const SingleActivator(LogicalKeyboardKey.digit2): () => _go('systems'),
        const SingleActivator(LogicalKeyboardKey.digit3): () => _go('vault'),
        const SingleActivator(LogicalKeyboardKey.digit4): () => _go('settings'),
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
                    OrbitRail(page: _activeRailPage, onGo: _go, short: short),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(osPad, 0, osPad, 0),
                            child: OrbitTopbar(
                              compact: short,
                              leading: OrbitIconButton(
                                icon: Icons.menu,
                                tooltip: 'Select system',
                                onPressed: _openSystemPicker,
                              ),
                            ),
                          ),
                          Expanded(child: _page()),
                          if (layout == OrbitLayout.desktop)
                            Padding(
                              padding: EdgeInsets.fromLTRB(osPad, 0, osPad, 6),
                              child: const OrbitFooter(),
                            ),
                        ],
                      ),
                    ),
                  ],
                )
              else
                Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(osPad, 6, osPad, 0),
                      child: OrbitTopbar(
                        centered: true,
                        leading: OrbitIconButton(
                          icon: Icons.menu,
                          tooltip: 'Select system',
                          onPressed: _openSystemPicker,
                        ),
                        trailing: OrbitIconButton(
                          icon: Icons.settings_outlined,
                          tooltip: 'Settings',
                          onPressed: () => _go('settings'),
                        ),
                      ),
                    ),
                    Expanded(child: _page()),
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
    final libIndex = 0, sysIndex = 1, vaultIndex = 2, settingsIndex = 3;
    final current = switch (page) {
      'systems' => sysIndex,
      'vault' => vaultIndex,
      'settings' => settingsIndex,
      _ => libIndex,
    };
    return IndexedStack(
      index: current,
      children: [
        LibraryScreen(
          state: widget.state,
          onGo: _go,
          filter: libraryFilter,
          onFilterChanged: _onLibraryFilterChanged,
        ),
        CoreManagerScreen(state: widget.state, onBrowseCore: _browseCore),
        VaultScreen(state: widget.state),
        SettingsScreen(state: widget.state, onGoVault: () => _go('vault')),
      ],
    );
  }
}
