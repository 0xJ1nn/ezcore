import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/local_data_dir.dart';
import 'state/app_state.dart';
import 'screens/core_manager_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/vault_screen.dart';
import 'theme/tokens.dart';
import 'widgets/orbit_widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Pins the mobile app-support dir before anything resolves paths.
  final dirProvider = await PlatformLocalDataDirProvider.resolve();
  runApp(EmuApp(dirProvider: dirProvider));
}

/// ezCORE — Orbit console shell (final-01).
/// 4 spaces: Library / Systems / Capsule / Settings.
/// Landscape ≥700px → left command rail; portrait → top command dock.
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
    state.load();
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
                  child: CircularProgressIndicator(color: Tokens.accent)),
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
  String? libraryCoreFilter;
  int libraryFilterNonce = 0;

  void _go(String p) => setState(() => page = p);

  void _browseCore(String coreId) {
    setState(() {
      libraryCoreFilter = 'core:$coreId';
      libraryFilterNonce++;
      page = 'library';
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.of(context).orientation;
    final wideRail = size.width >= 700 && orientation == Orientation.landscape;
    final short = size.height <= 650 && wideRail;
    final portrait = !wideRail;
    final osPad = Tokens.osPad(size.width,
        portrait: portrait, short_: short && wideRail);
    final compactTop = wideRail ? (short ? 32.0 : 66.0) : 68.0;

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
              Ambient(
                  motion:
                      widget.state.settings['motion'] != false),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (wideRail)
                    OrbitRail(page: page, onGo: _go, short: short),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (wideRail)
                          Padding(
                            padding:
                                EdgeInsets.fromLTRB(osPad, 0, osPad, 0),
                            child: SizedBox(
                              height: compactTop,
                              child: const OrbitTopbar(compact: true),
                            ),
                          )
                        else
                          Padding(
                            padding:
                                EdgeInsets.fromLTRB(osPad, 0, osPad, 0),
                            child: SizedBox(
                              height: 118,
                              child: Column(
                                children: [
                                  const SizedBox(height: 16),
                                  const Row(
                                    children: [
                                      Expanded(
                                          child: OrbitTopbar(
                                              compact: true)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  OrbitDockNav(
                                      page: page, onGo: _go),
                                ],
                              ),
                            ),
                          ),
                        Expanded(child: _page()),
                        if (size.width >= 700)
                          Padding(
                            padding:
                                EdgeInsets.fromLTRB(osPad, 0, osPad, 6),
                            child: const OrbitFooter(),
                          ),
                      ],
                    ),
                  ),
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
          initialFilter: libraryCoreFilter,
          key: ValueKey('lib-$libraryFilterNonce-${libraryCoreFilter ?? ''}'),
        ),
        CoreManagerScreen(
          state: widget.state,
          onBrowseCore: _browseCore,
        ),
        VaultScreen(state: widget.state),
        SettingsScreen(
          state: widget.state,
          onGoVault: () => _go('vault'),
        ),
      ],
    );
  }
}
