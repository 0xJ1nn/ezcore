// The phone layout editor is an in-place board: a banner over the game,
// dashed outlines on unselected controls, and a selected group with a scale
// label and resize handles. These tests drive that board, not a side panel.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class _Dir implements LocalDataDirProvider {
  _Dir(this.dir);
  final Directory dir;
  @override
  Future<Directory> localDataDir() async => dir;
  @override
  String localDataDirPath() => dir.path;
}

final _boardKey = GlobalKey();

Future<ui.Image> _frame(WidgetTester t) async {
  final image = await t.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 240, 160),
      Paint()..color = const Color(0xFF1E294E),
    );
    final picture = recorder.endRecording();
    return picture.toImage(240, 160);
  });
  return image!;
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('ezcore_edit_board'));
  tearDown(() => tmp.deleteSync(recursive: true));

  AppState mk() => AppState.internal(
    persistence: PersistenceService(_Dir(tmp)),
    saves: LocalSaveSyncProvider(tmp),
  );

  Future<LayoutStore> pumpEditor(WidgetTester t) async {
    t.view.physicalSize = const Size(844, 390);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = LayoutStore(mk());
    final frame = await _frame(t);
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: RepaintBoundary(
          key: _boardKey,
          child: LayoutEditorScreen(
            store: store,
            system: 'gba',
            portrait: false,
            frame: frame,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return store;
  }

  Future<ByteData> boardPixels(WidgetTester t) async {
    final bytes = await t.runAsync(() async {
      final ro =
          _boardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    });
    return bytes!;
  }

  int at(ByteData px, int x, int y) {
    final i = (y * 844 + x) * 4;
    return (px.getUint8(i) << 16) |
        (px.getUint8(i + 1) << 8) |
        px.getUint8(i + 2);
  }

  testWidgets('the board is a banner over the game, not a side panel', (
    t,
  ) async {
    await pumpEditor(t);
    expect(find.text('Drag to move · pinch to resize'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
    // The bottom action pills keep their hit areas but draw nothing here.
    expect(find.byKey(const ValueKey('edit-menu')), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-start')), findsOneWidget);
    // The game picture is still on the board behind the controls.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('tapping a face button selects the group and offers resize', (
    t,
  ) async {
    await pumpEditor(t);
    await t.tap(find.byKey(const ValueKey('edit-a')));
    await t.pump();
    expect(find.text('100%'), findsOneWidget);
    await t.tap(find.text('100%'));
    await t.pump();
    expect(find.byTooltip('Bigger'), findsOneWidget);
    expect(find.byTooltip('Smaller'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byTooltip('Bigger'));
      await t.pump();
    }
    expect(find.text('112%'), findsOneWidget);
  });

  testWidgets(
    'the landscape board starts A high right and B low left, resized to the printed box',
    (t) async {
      final store = await pumpEditor(t);
      await t.tap(find.byKey(const ValueKey('edit-a')));
      await t.pump();
      await t.tap(find.byKey(const Key('edit-scale-label')));
      await t.pump();
      for (var i = 0; i < 3; i++) {
        await t.tap(find.byTooltip('Bigger'));
        await t.pump();
      }
      expect(find.text('112%'), findsOneWidget);
      await t.tap(find.text('Done'));
      await t.pumpAndSettle();
      final layout = store.resolve('gba', portrait: false);
      Rect box(String id) => layout.controls
          .firstWhere((c) => c.id == id)
          .rect
          .resolve(844, 390);
      final a = box('a').center, b = box('b').center;
      expect(a.dx, greaterThan(b.dx));
      expect(a.dy, lessThan(b.dy));
      expect(a.dx, closeTo(767, 3));
      expect(a.dy, closeTo(184.5, 3));
      expect(b.dx, closeTo(692, 3));
      expect(b.dy, closeTo(240.5, 3));
    },
  );

  testWidgets('the selected glyphs stay bright and the outline never blooms', (
    t,
  ) async {
    await pumpEditor(t);
    await t.tap(find.byKey(const ValueKey('edit-a')));
    await t.pumpAndSettle();
    final pixels = await boardPixels(t);
    var bright = false;
    for (var y = 170; y <= 205; y++) {
      for (var x = 746; x <= 782; x++) {
        final c = at(pixels, x, y);
        if ((c >> 16) > 200 && ((c >> 8) & 0xFF) > 200 && (c & 0xFF) > 200) {
          bright = true;
        }
      }
    }
    expect(bright, isTrue, reason: 'A is drawn in the design’s #DDE6F4');
    final fill = at(pixels, 763, 165);
    expect(fill >> 16, inInclusiveRange(25, 35));
    expect((fill >> 8) & 0xFF, inInclusiveRange(40, 52));
    expect(fill & 0xFF, inInclusiveRange(58, 70));
    // The old bloom lit the stage well outside the outline; it must be dark.
    expect(at(pixels, 830, 200) & 0xFF, lessThan(80));
  });

  testWidgets('the scale label is centred above the selection box', (t) async {
    await pumpEditor(t);
    await t.tap(find.byKey(const ValueKey('edit-a')));
    await t.pump();
    final outline = find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          w.painter.runtimeType.toString() == '_SelectionOutlinePainter',
    );
    final outlinePos = t.widget<Positioned>(
      find.ancestor(of: outline, matching: find.byType(Positioned)).first,
    );
    final labelPos = t.widget<Positioned>(
      find
          .ancestor(
            of: find.byKey(const Key('edit-scale-label')),
            matching: find.byType(Positioned),
          )
          .first,
    );
    expect(labelPos.top!, lessThan(outlinePos.top!));
    expect(labelPos.left, closeTo(outlinePos.left!, 1e-9));
    expect(labelPos.width, closeTo(outlinePos.width!, 1e-9));
  });

  testWidgets('Done saves the edited layout for this system', (t) async {
    final store = await pumpEditor(t);
    await t.drag(find.byKey(const ValueKey('edit-a')), const Offset(-20, 0));
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(store.isCustomised('gba_landscape'), isTrue);
  });

  testWidgets('long-press hides a button; Menu can never be hidden', (t) async {
    final store = await pumpEditor(t);
    await t.longPress(find.byKey(const ValueKey('edit-l')));
    await t.pump();
    expect(
      store.resolve('gba', portrait: false).controls.map((c) => c.id),
      contains('b'),
      reason: 'nothing is saved until Done',
    );
    expect(find.text('Show hidden (1)'), findsOneWidget);
    await t.longPress(find.byKey(const ValueKey('edit-menu')));
    await t.pump();
    expect(find.text('Show hidden (2)'), findsNothing);
  });

  testWidgets('the faded slider changes the saved opacity', (t) async {
    final store = await pumpEditor(t);
    final slider = t.widget<Slider>(find.byType(Slider));
    slider.onChanged!(0.4);
    await t.pump();
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(store.resolve('gba', portrait: false).opacity, closeTo(0.4, 1e-9));
  });

  test('every built-in board still validates after the phone mapping', () {
    for (final portrait in [true, false]) {
      for (final system in ['gba', 'nds', 'snes']) {
        final layout = builtinLayout(system, portrait: portrait);
        final parsed = ControlLayout.parse(layout.toJson());
        expect(parsed.errors, isEmpty, reason: '$system/$portrait');
      }
    }
  });
}
