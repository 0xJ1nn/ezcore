// T18: the empty, loading and error states from handoff §8.1 and §8.10.
// Each state is a small public widget, so the tests lock its copy, actions
// and geometry without depending on a whole app boot.
import 'dart:convert';

import 'package:flutter/gestures.dart' show kSecondaryButton, PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/screens/launch.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/input_mode.dart';
import 'package:ezcore/theme/symbols.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/context_menu.dart';
import 'package:ezcore/widgets/crash_recovery.dart';
import 'package:ezcore/widgets/empty_library.dart';
import 'package:ezcore/widgets/launch_error.dart';
import 'package:ezcore/widgets/library_skeleton.dart';

/// Large asset strings decode on an isolate, which never completes inside a
/// widget test's fake clock — load once in the real-async setUpAll.
Map<String, dynamic>? _catalog;

Future<void> _loadCatalog() async {
  final data = await rootBundle.loadString('cores/catalog.json');
  _catalog = json.decode(data) as Map<String, dynamic>;
}

void _install(AppState s, String id) {
  final catalog = _catalog!;
  s.registry.loadCatalog({
    for (final e in catalog.entries) e.key: json.encode(e.value),
  });
  final manifest = s.registry.catalog.firstWhere((c) => c.id == id);
  final sha = manifest.artifacts.values.isEmpty
      ? 'fixture'
      : manifest.artifacts.values.first;
  s.registry.install(manifest, expectedSha256: sha);
}

Widget _host(Widget child) => MaterialApp(theme: Tokens.theme(), home: Scaffold(body: child));

/// Fixed pumps: the skeleton and dialogs have animations, so pumpAndSettle
/// can wait forever on a repeating controller.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    await _loadCatalog();
  });

  group('empty library', () {
    testWidgets('shows five ghost covers, the copy and both routes', (t) async {
      var added = 0;
      var systems = 0;
      await t.pumpWidget(_host(EmptyLibrary(
        phone: true,
        onAddGames: () => added++,
        onOpenSystems: () => systems++,
      )));

      expect(find.byKey(const Key('ghost-cover')), findsNWidgets(5));
      expect(find.text('Your shelf is empty'), findsOneWidget);
      expect(
        find.textContaining('ezCORE ships no games. Point it at a folder'),
        findsOneWidget,
      );
      expect(find.text('Add games'), findsOneWidget);
      const systemsButton = 'Open Systems';
      expect(find.text(systemsButton), findsOneWidget);
      await t.ensureVisible(find.text('Add games'));
      await settle(t);
      await t.tap(find.text('Add games'));
      await t.ensureVisible(find.text(systemsButton));
      await settle(t);
      await t.tap(find.text(systemsButton));
      expect(added, 1);
      expect(systems, 1);
    });

    testWidgets('falls back to Choose a folder with no Systems route', (t) async {
      await t.pumpWidget(_host(EmptyLibrary(phone: true, onAddGames: () {})));
      expect(find.text('Choose a folder'), findsOneWidget);
      expect(find.text('Open Systems'), findsNothing);
    });
  });

  testWidgets('loading skeleton shows the shimmer and reading note', (t) async {
    await t.pumpWidget(_host(const LibrarySkeleton()));
    expect(find.byKey(const Key('library-skeleton')), findsOneWidget);
    expect(find.text('Reading your collection…'), findsOneWidget);
  });

  testWidgets('HomeScreen routes empty and loading to the new states', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = AppState.ephemeral();
    await t.pumpWidget(_host(HomeScreen(state: s, onOpenCores: () {})));
    await settle(t);
    expect(find.byType(EmptyLibrary), findsOneWidget);

    await t.pumpWidget(_host(HomeScreen(state: s, loading: true)));
    await t.pump();
    expect(find.byType(LibrarySkeleton), findsOneWidget);
  });

  group('blocked launch', () {
    testWidgets('missing BIOS names the file and routes to Systems without a download',
        (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = AppState.ephemeral();
      _install(s, 'geometry1');
      s.games = [
        const GameEntry(
          id: 'glass',
          title: 'Glasswing',
          system: 'psx',
          extension: 'cue',
          coreId: 'geometry1',
          filePath: '/Games/glass.cue',
        ),
      ];
      late BuildContext ctx;
      await t.pumpWidget(_host(Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      )));
      // Drive the launcher directly: a tap would wait on the dialog route's
      // transition, which is not what this state test is checking.
      launchGame(ctx, s, s.games.first);
      await settle(t);

      expect(find.text('BIOS file needed'), findsOneWidget);
      expect(find.textContaining('scph5501.bin'), findsOneWidget);
      expect(find.textContaining('never downloads'), findsOneWidget);
      expect(find.text('Got it'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is LaunchErrorSheet),
        findsOneWidget,
      );
    });

    testWidgets('the sheet returns the chosen route', (t) async {
      Object? chosen;
      await t.pumpWidget(_host(LaunchErrorSheet<String>(
        title: 'BIOS file needed',
        body: 'Copy the dump you own into your games folder.',
        icon: Symbols.memory,
        actions: const [
          LaunchErrorAction(label: 'Got it', value: 'ok', primary: true),
          LaunchErrorAction(label: 'See core details', value: 'systems'),
        ],
        onSelected: (value) => chosen = value,
      )));
      await t.tap(find.text('See core details'));
      expect(chosen, 'systems');
    });

    testWidgets('missing core offers Open Systems', (t) async {
      final s = AppState.ephemeral();
      s.games = [
        const GameEntry(
          id: 'unknown',
          title: 'Unknown Dump',
          system: 'psx',
          extension: 'zzz',
          coreId: '',
          filePath: '/Games/unknown.zzz',
        ),
      ];
      late BuildContext ctx;
      await t.pumpWidget(_host(Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox.shrink();
        },
      )));
      launchGame(ctx, s, s.games.first);
      await settle(t);
      expect(find.textContaining('isn’t installed'), findsOneWidget);
      expect(find.text('Open Systems'), findsOneWidget);
      expect(find.text('Not now'), findsOneWidget);
    });
  });

  group('crash recovery', () {
    testWidgets('names the game, offers recovery first and returns the choice',
        (t) async {
      CrashRecoveryChoice? choice;
      await t.pumpWidget(_host(CrashRecoveryDialog(
        gameTitle: 'Tidal Arcana',
        onSelected: (c) => choice = c,
      )));
      expect(find.text('Tidal Arcana stopped unexpectedly'), findsOneWidget);
      expect(find.textContaining('Crash protection kept ezCORE running'), findsOneWidget);
      expect(find.text('Resume from snapshot'), findsOneWidget);
      expect(find.text('Back to library'), findsOneWidget);
      expect(
        find.text('If this keeps happening, try another core for this system.'),
        findsOneWidget,
      );
      await t.tap(find.text('Resume from snapshot'));
      expect(choice, CrashRecoveryChoice.resume);
    });
  });

  group('pointer menu', () {
    testWidgets('lists the same actions with their shortcuts', (t) async {
      Object? selected;
      await t.pumpWidget(_host(ContextMenu<String>(
        items: const [
          ContextMenuItem(label: 'Resume', icon: Symbols.playArrow, value: 'resume', shortcut: 'Enter'),
          ContextMenuItem(label: 'Show file', icon: Symbols.folderOpen, value: 'file'),
          ContextMenuItem(label: 'Remove from collection', icon: Symbols.delete, value: 'remove', shortcut: 'Del', danger: true),
        ],
        onSelected: (value) => selected = value,
      )));
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Enter'), findsOneWidget);
      expect(find.text('Show file'), findsOneWidget);
      expect(find.text('Del'), findsOneWidget);
      await t.tap(find.text('Show file'));
      expect(selected, 'file');
    });

    testWidgets('right-click on the library opens the menu at the pointer', (t) async {
      t.view.physicalSize = const Size(1180, 820);
      t.view.devicePixelRatio = 1;
      InputMode.shared.notePointer();
      addTearDown(() {
        t.view.reset();
        InputMode.shared.reset();
      });
      final s = AppState.ephemeral()
        ..games = [
          const GameEntry(
            id: 'g',
            title: 'My Dump',
            system: 'gba',
            extension: 'gba',
            coreId: 'advancebit',
            filePath: '/Games/dump.gba',
          ),
        ];
      await t.pumpWidget(_host(HomeScreen(state: s)));
      await settle(t);
      await t.tapAt(
        const Offset(200, 200),
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
      );
      await settle(t);
      expect(find.byType(ContextMenu<String>), findsOneWidget);
      expect(find.text('Show file'), findsOneWidget);
    });

    testWidgets('the favorites row follows the game, with an outline heart to add',
        (t) async {
      t.view.physicalSize = const Size(1180, 820);
      t.view.devicePixelRatio = 1;
      InputMode.shared.notePointer();
      addTearDown(() {
        t.view.reset();
        InputMode.shared.reset();
      });
      final s = AppState.ephemeral()
        ..games = [
          const GameEntry(
            id: 'g',
            title: 'My Dump',
            system: 'gba',
            extension: 'gba',
            coreId: 'advancebit',
            filePath: '/Games/dump.gba',
          ),
        ];
      await t.pumpWidget(_host(HomeScreen(state: s)));
      await settle(t);

      Future<void> openMenu() async {
        await t.tapAt(
          const Offset(200, 200),
          buttons: kSecondaryButton,
          kind: PointerDeviceKind.mouse,
        );
        await settle(t);
      }

      await openMenu();
      expect(find.text('Add to favorites'), findsOneWidget);
      expect(find.text('Remove from favorites'), findsNothing);
      final heart = t.widget<Icon>(
        find.descendant(
          of: find.byType(ContextMenu<String>),
          matching: find.byIcon(Symbols.favorite),
        ),
      );
      expect(heart.icon, Symbols.favorite);
      expect(heart.fill, isNot(1));

      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(t);
      s.toggleFavorite('g');
      await settle(t);
      await openMenu();
      expect(find.text('Remove from favorites'), findsOneWidget);
      expect(find.text('Add to favorites'), findsNothing);
    });
  });
}
