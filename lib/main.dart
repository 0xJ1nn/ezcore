import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'cores/core_registry.dart';
import 'screens/core_manager_screen.dart';
import 'screens/library_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/tokens.dart';

void main() {
  runApp(const EmuApp());
}

/// Working title build — rebrand pending name decision.
class EmuApp extends StatefulWidget {
  const EmuApp({super.key});

  @override
  State<EmuApp> createState() => _EmuAppState();
}

class _EmuAppState extends State<EmuApp> {
  late final AppState state;

  @override
  void initState() {
    super.initState();
    state = AppState();
    state.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ezCore',
      debugShowCheckedModeBanner: false,
      theme: Tokens.theme(),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          if (!state.loaded) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.loadError != null && kReleaseMode == false) {
            // Non-fatal in debug: show shell anyway once catalog exists.
            if (state.registry.catalog.isEmpty) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Tokens.pad),
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
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      LibraryScreen(state: widget.state),
      CoreManagerScreen(state: widget.state),
      SettingsScreen(state: widget.state),
    ];
    return Scaffold(
      appBar: AppBar(
        leading: index != 0
            ? IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back, size: 20),
                onPressed: () => setState(() => index = 0),
              )
            : null,
        title: const Text('ezCore'),
        actions: [
          ListenableBuilder(
            listenable: widget.state.registry,
            builder: (context, _) {
              final updates = widget.state.registry.catalog
                  .where((m) =>
                      widget.state.registry.statusOf(m) ==
                      CoreStatus.updateAvailable)
                  .length;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    tooltip: 'Cores',
                    icon: const Icon(Icons.extension_outlined),
                    onPressed: () => setState(() => index = 1),
                  ),
                  if (updates > 0)
                    const Positioned(
                      right: 8,
                      top: 8,
                      child: CircleAvatar(radius: 5),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension_outlined),
            selectedIcon: Icon(Icons.extension),
            label: 'Cores',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
