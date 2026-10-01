// Users can make on-screen controls their own: move, resize, hide, fade,
// save, and reset to default. These drive the real editor with gestures and
// check what gets saved, and that a saved layout survives only while valid.
import 'dart:io';

import 'package:ezcore/controls/builtin_layouts.dart';
import 'package:ezcore/controls/control_layout.dart';
import 'package:ezcore/controls/layout_editor.dart';
import 'package:ezcore/controls/layout_store.dart';
import 'package:ezcore/services/local_data_dir.dart';
import 'package:ezcore/services/persistence_service.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/state/save_sync.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Dir implements LocalDataDirProvider {
  _Dir(this.dir);
  final Directory dir;
  @override
  Future<Directory> localDataDir() async => dir;
  @override
  String localDataDirPath() => dir.path;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ezcore_layouts'));
  tearDown(() => tmp.deleteSync(recursive: true));

  AppState mk() => AppState.internal(
    persistence: PersistenceService(_Dir(tmp)),
    saves: LocalSaveSyncProvider(tmp),
  );

  group('LayoutStore', () {
    test('no saved layout means the built-in', () {
      final store = LayoutStore(mk());
      expect(
        store.resolve('gba', portrait: true),
        same(builtinLayout('gba', portrait: true)),
      );
    });

    test(
      'a saved layout replaces the built-in, as one stable instance',
      () async {
        final store = LayoutStore(mk());
        final base = builtinLayout('gba', portrait: true);
        await store.save(base.copyWith(opacity: 0.4));
        final a = store.resolve('gba', portrait: true);
        expect(a.opacity, 0.4);
        expect(
          store.resolve('gba', portrait: true),
          same(a),
          reason: 'per-frame rebuilds must get the same instance',
        );
        expect(store.isCustomised(base.id), isTrue);
      },
    );

    test('reset brings the built-in back', () async {
      final store = LayoutStore(mk());
      final base = builtinLayout('snes', portrait: false);
      await store.save(base.copyWith(opacity: 0.3));
      await store.reset(base.id);
      expect(store.resolve('snes', portrait: false), same(base));
    });

    test(
      'a corrupt or mismatched saved layout is ignored, not fatal',
      () async {
        final state = mk();
        final store = LayoutStore(state);
        final base = builtinLayout('psx', portrait: true);
        await state.setSetting(customLayoutsKey, {
          base.id: {
            'format': 'ezcore.controls/1',
            'id': base.id,
            'nonsense': 1,
          },
        });
        expect(store.resolve('psx', portrait: true), same(base));
        await state.setSetting(customLayoutsKey, {
          base.id: builtinLayout('gba', portrait: true).toJson(), // wrong id
        });
        expect(store.resolve('psx', portrait: true), same(base));
      },
    );

    test('an invalid layout cannot be saved', () async {
      final store = LayoutStore(mk());
      final base = builtinLayout('gba', portrait: true);
      final broken = base.copyWith(
        controls: [
          ...base.controls,
          base.controls.first, // duplicate id
        ],
      );
      expect(() => store.save(broken), throwsArgumentError);
    });
  });

  group('LayoutEditorScreen', () {
    Future<LayoutStore> pump(WidgetTester t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      // In memory: real file I/O never completes under the widget-test clock.
      final store = LayoutStore(AppState.ephemeral());
      await t.pumpWidget(
        MaterialApp(
          theme: Tokens.theme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => LayoutEditorScreen(
                        store: store,
                        system: 'gba',
                        portrait: true,
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      return store;
    }

    ControlSpec ctl(ControlLayout l, String id) =>
        l.controls.firstWhere((c) => c.id == id);

    testWidgets('dragging a control moves it, and Save keeps it', (t) async {
      final store = await pump(t);
      final before = ctl(builtinLayout('gba', portrait: true), 'a').rect;
      await t.drag(
        find.byKey(const ValueKey('edit-a')),
        const Offset(-60, -40),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final after = ctl(store.resolve('gba', portrait: true), 'a').rect;
      expect(after.x, lessThan(before.x));
      expect(after.y, lessThan(before.y));
      expect(after.w, closeTo(before.w, 1e-9), reason: 'moving keeps size');
    });

    testWidgets('a control can be made bigger and is kept on screen', (
      t,
    ) async {
      final store = await pump(t);
      final before = ctl(builtinLayout('gba', portrait: true), 'start').rect;
      await t.tap(find.byKey(const ValueKey('edit-start')));
      await t.pump();
      for (var i = 0; i < 30; i++) {
        await t.tap(find.byTooltip('Bigger'));
      }
      await t.pump();
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final after = ctl(store.resolve('gba', portrait: true), 'start').rect;
      expect(after.w, greaterThan(before.w));
      expect(after.x + after.w, lessThanOrEqualTo(1.0 + 1e-9));
      expect(after.y + after.h, lessThanOrEqualTo(1.0 + 1e-9));
    });

    testWidgets('a control can be hidden — but never Menu', (t) async {
      final store = await pump(t);
      await t.tap(find.byKey(const ValueKey('edit-menu')));
      await t.pump();
      expect(
        find.byTooltip('Hide'),
        findsNothing,
        reason: 'Menu is the touch way out of a game',
      );
      await t.tap(find.byKey(const ValueKey('edit-select')));
      await t.pump();
      await t.tap(find.byTooltip('Hide'));
      await t.pump();
      expect(find.text('Show hidden (1)'), findsOneWidget);
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      final saved = store.resolve('gba', portrait: true);
      expect(saved.controls.map((c) => c.id), isNot(contains('select')));
      expect(saved.controls.map((c) => c.id), contains('menu'));
    });

    testWidgets('Cancel saves nothing; Reset to default clears a saved copy', (
      t,
    ) async {
      final store = await pump(t);
      await t.drag(find.byKey(const ValueKey('edit-b')), const Offset(30, 0));
      await t.pump();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(store.isCustomised('gba_portrait'), isFalse);

      await store.save(
        builtinLayout('gba', portrait: true).copyWith(opacity: 0.5),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.text('Reset to default'));
      await t.pumpAndSettle();
      expect(store.isCustomised('gba_portrait'), isFalse);
    });
  });
}
