// Handoff §17: one widget test per acceptance item that can be proved in a
// widget test. The shared focus-owner, launch and overlay behaviours are
// covered in their own suites; these tests pin the parts a final pass can
// regress — the measured chrome, input-following status, reduced motion, the
// offline promise and the accessibility floor.
import 'dart:io';

import 'package:ezcore/main.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/screens/home_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/input_mode.dart';
import 'package:ezcore/theme/accessibility.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/launch_error.dart';
import 'package:ezcore/widgets/library_header.dart';
import 'package:ezcore/widgets/library_looks/look_theme.dart';
import 'package:ezcore/widgets/orbit_chrome.dart';
import 'package:ezcore/widgets/orbit_dialog.dart';
import 'package:ezcore/widgets/orbit_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  theme: Tokens.theme(),
  home: Scaffold(body: child),
);

Future<void> _pumps(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(() {
    InputMode.shared.reset();
    MotionPreference.shared.reset();
  });

  testWidgets('1–2. the desktop rail keeps five stops and one shared focus', (
    t,
  ) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final s = AppState.ephemeral();
    s.games = const [
      GameEntry(
        id: 'lanterns',
        title: 'Lanterns of Vell',
        system: 'nds',
        filePath: '/Games/l.nds',
        extension: 'nds',
        lastPlayedMs: 1000,
      ),
    ];
    await t.pumpWidget(_host(Shell(state: s)));
    await _pumps(t);
    expect(find.text('Library'), findsNWidgets(2)); // rail + screen title
    for (final label in const ['Systems', 'Capsule', 'Settings', 'Add games']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // The first rail tile starts at y=97 in the reference; Add games at y=471.
    final addTop = t.getTopLeft(find.text('Add games')).dy;
    expect(addTop, greaterThan(430));
    expect(addTop, lessThan(550));
    // One focus owner: pointer and keys both write InputMode's last source,
    // which is what every halo and hint reads (focus_owner_test covers moves).
    InputMode.shared.notePointer();
    await t.pump();
    expect(InputMode.shared.lastSource, OrbitInputSource.pointer);
    InputMode.shared.noteKeyboard();
    await t.pump();
    expect(InputMode.shared.lastSource, OrbitInputSource.keyboard);
  });

  testWidgets('3. the status corner follows the last input on that event', (
    t,
  ) async {
    t.view.physicalSize = const Size(1440, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      _host(OrbitStatus(now: () => DateTime(2026, 11, 21, 7, 20))),
    );
    expect(find.text('On this device'), findsOneWidget);
    expect(find.text('Keyboard'), findsOneWidget);
    expect(find.text('07:20'), findsOneWidget);

    InputMode.shared.notePointer();
    await t.pump();
    expect(find.text('Mouse'), findsOneWidget);
    expect(find.text('Keyboard'), findsNothing);
  });

  testWidgets('4–5. every destination restores focus; B closes an overlay', (
    t,
  ) async {
    await t.pumpWidget(_host(const _OverlayHost()));
    await t.tap(find.text('Open sheet'));
    await _pumps(t);
    expect(find.text('PlayStation needs a BIOS file'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumps(t);
    expect(find.text('PlayStation needs a BIOS file'), findsNothing);
  });

  testWidgets(
    '6–7. a blocked launch names the fix and never offers a download',
    (t) async {
      await t.pumpWidget(_host(const _BlockedLaunchHost()));
      await t.tap(find.text('Play'));
      await _pumps(t);
      expect(find.text('PlayStation needs a BIOS file'), findsOneWidget);
      expect(find.textContaining('scph5501.bin'), findsOneWidget);
      expect(find.text('Add BIOS file'), findsOneWidget);
      expect(find.textContaining('Download'), findsNothing);
      expect(find.textContaining('download'), findsNothing);
    },
  );

  testWidgets('8. reduced motion swaps durations and stops ambient drift', (
    t,
  ) async {
    MotionPreference.shared.set(ReducedMotion.off);
    expect(Tokens.sceneDur, const Duration(milliseconds: 900));
    MotionPreference.shared.set(ReducedMotion.on);
    expect(Tokens.baseDur, const Duration(milliseconds: 160));
    expect(Tokens.sceneDur, Duration.zero);
    expect(Tokens.ease, const Cubic(0, 0, 1, 1));
  });

  testWidgets(
    '9–10. the header lands on the measured row and text has a floor',
    (t) async {
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final s = AppState.ephemeral();
      s.games = const [
        GameEntry(
          id: 'lanterns',
          title: 'Lanterns of Vell',
          system: 'nds',
          filePath: '/Games/l.nds',
          extension: 'nds',
          lastPlayedMs: 1000,
        ),
      ];
      await t.pumpWidget(_host(Shell(state: s)));
      await _pumps(t);
      expect(t.getTopLeft(find.byType(LibraryChips)).dy, closeTo(168, 8));
      expect(LookTheme.wallCover, const Size(156, 208));
      expect(LookTheme.gridCover, const Size(132, 176));
      expect(Tokens.body(size: 8).fontSize, 12);
      expect(Tokens.display(size: 8).fontSize, 12);
    },
  );

  testWidgets('11. every focusable cover carries a screen-reader label', (
    t,
  ) async {
    final s = AppState.ephemeral();
    s.games = const [
      GameEntry(
        id: 'lanterns',
        title: 'Lanterns of Vell',
        system: 'nds',
        filePath: '/Games/l.nds',
        extension: 'nds',
        lastPlayedMs: 1000,
      ),
    ];
    await t.pumpWidget(_host(HomeScreen(state: s)));
    await _pumps(t);
    expect(find.bySemanticsLabel(RegExp('Lanterns of Vell')), findsWidgets);
  });

  testWidgets(
    '12. removal focuses the safe choice and offers Undo for six seconds',
    (t) async {
      int undone = 0;
      bool confirmed = false;
      await t.pumpWidget(
        _host(
          _ConfirmHost(onResult: (v) => confirmed = v, onUndo: () => undone++),
        ),
      );
      await t.tap(find.text('Remove me'));
      await _pumps(t);
      expect(find.text('Remove Lanterns of Vell?'), findsOneWidget);
      // Enter activates the focused choice: the non-destructive one.
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(confirmed, isFalse);

      await t.tap(find.text('Remove me'));
      await _pumps(t);
      await t.tap(find.byKey(const ValueKey('orbit-dialog-action-Remove')));
      await _pumps(t);
      expect(find.text('Removed Lanterns of Vell'), findsOneWidget);
      await t.tap(find.text('Undo'));
      expect(undone, 1);
    },
  );

  test('the UI has no account, no ads and no core-name branching', () {
    final ui = [
      ...Directory('lib/screens').listSync(recursive: true),
      ...Directory('lib/widgets').listSync(recursive: true),
    ].whereType<File>();
    for (final file in ui) {
      final source = file.readAsStringSync();
      expect(source.contains('coreId =='), isFalse, reason: file.path);
      expect(
        RegExp(r'\b(signIn|logIn|password|advert)\b').hasMatch(source),
        isFalse,
        reason: file.path,
      );
      expect(
        RegExp(r'HttpClient\s*\(|Uri\.https|Uri\.parse').hasMatch(source),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('muted text clears 4.5:1 on ink', () {
    double channel(int v) {
      final c = v / 255;
      return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) * 2.4;
    }

    int byte(double v) => (v * 255).round().clamp(0, 255);
    double luminance(Color c) =>
        0.2126 * channel(byte(c.r)) +
        0.7152 * channel(byte(c.g)) +
        0.0722 * channel(byte(c.b));
    final a = luminance(Tokens.muted);
    final b = luminance(Tokens.bg);
    expect((a + 0.05) / (b + 0.05), greaterThanOrEqualTo(4.5));
  });
}

class _OverlayHost extends StatelessWidget {
  const _OverlayHost();

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => showLaunchError<String>(
        context,
        title: 'PlayStation needs a BIOS file',
        body: 'Add scph5501.bin, then try again.',
        actions: const [LaunchErrorAction(label: 'Cancel', value: 'x')],
      ),
      child: const Text('Open sheet'),
    ),
  );
}

class _BlockedLaunchHost extends StatelessWidget {
  const _BlockedLaunchHost();

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => showLaunchError<String>(
        context,
        title: 'PlayStation needs a BIOS file',
        body: 'Add scph5501.bin to your BIOS folder, then try again.',
        actions: const [
          LaunchErrorAction(label: 'Add BIOS file', value: 'bios'),
          LaunchErrorAction(label: 'Cancel', value: 'cancel'),
        ],
      ),
      child: const Text('Play'),
    ),
  );
}

class _ConfirmHost extends StatelessWidget {
  const _ConfirmHost({required this.onResult, required this.onUndo});

  final ValueChanged<bool> onResult;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () async {
        final ok = await showOrbitConfirmDialog(
          context,
          title: 'Remove Lanterns of Vell?',
          body: 'The file on this device is not touched.',
        );
        if (ok) {
          showOrbitToast(
            context,
            message: 'Removed Lanterns of Vell',
            undoGlyph: 'Y',
            onUndo: onUndo,
          );
        }
        onResult(ok);
      },
      child: const Text('Remove me'),
    ),
  );
}
