// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// Renders the Diamond frames to PNG for the design pixel review. Output goes
// to EZCORE_CAPTURE_DIR (set by the capture run) or a temp folder; no capture
// artefacts are written into the app repository.
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:ezcore/screens/settings_screen.dart';
import 'package:ezcore/state/app_state.dart';
import 'package:ezcore/support/entitlement.dart';
import 'package:ezcore/support/plans_sheet.dart';
import 'package:ezcore/support/purchase_store.dart';
import 'package:ezcore/support/thanks_overlay.dart';
import 'package:ezcore/support/tips_sheet.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'font_loading.dart';
import 'support_fake_store.dart';

void main() {
  final out = Directory(
    Platform.environment['EZCORE_CAPTURE_DIR'] ??
        '${Directory.systemTemp.path}/ezcore-diamond-captures',
  );

  setUpAll(() async => loadBundledFonts());

  Future<void> capture(
    WidgetTester tester, {
    required String name,
    required Size size,
    required Widget Function(Entitlement entitlement) build,
    Map<String, dynamic>? storage,
    bool trialEligible = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final entitlement = Entitlement(
      store: FakePurchaseStore(trialEligible: trialEligible),
      storage: InMemorySupportStorage(storage),
    );
    addTearDown(entitlement.dispose);
    await entitlement.start();

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: Tokens.bg,
              child: SizedBox.expand(child: build(entitlement)),
            ),
          ),
        ),
      ),
    );
    // Bounded pumps: full settling can chase the store-restore timer. The
    // real-async gap lets the rendered gem assets finish decoding.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    final boundary = key.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
    // toImage reads back from the raster thread, so it must run outside the
    // widget tester's fake-async zone.
    final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
    final bytes = (await tester.runAsync(
      () => image.toByteData(format: ImageByteFormat.png),
    ))!;
    if (!out.existsSync()) out.createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
  }

  Widget settings(Entitlement entitlement) => SettingsScreen(
        state: AppState.ephemeral(),
        entitlement: entitlement,
        initialTab: 'Diamond',
      );

  Widget over(
    Entitlement entitlement,
    Widget sheet, {
    Color scrim = const Color(0x9E03060C),
  }) =>
      Stack(
        children: [
          settings(entitlement),
          Positioned.fill(child: ColoredBox(color: scrim)),
          Align(alignment: Alignment.bottomCenter, child: sheet),
        ],
      );

  const desktop = Size(1440, 900);
  const phone = Size(390, 844);
  final memberStorage = <String, dynamic>{
    'diamond.member': true,
    'diamond.plan': diamondYearlyId,
    'diamond.renew':
        DateTime(2027, 11, 18).millisecondsSinceEpoch,
    'tip.tally': {'tip.coffee': 3, 'tip.pizza': 1},
  };
  final thanksStorage = <String, dynamic>{
    'tip.tally': {'tip.coffee': 3, 'tip.pizza': 2},
  };

  for (final (device, size) in [
    ('desktop', desktop),
    ('phone', phone),
  ]) {
    testWidgets('$device Diamond captures', (tester) async {
      await capture(
        tester,
        name: '${device}_1_not_member',
        size: size,
        build: settings,
      );
      await capture(
        tester,
        name: '${device}_2_plans',
        size: size,
        trialEligible: true,
        build: (e) => over(
          e,
          PlansSheet(
            products: e.products,
            trialEligible: e.trialEligible,
          ),
        ),
      );
      await capture(
        tester,
        name: '${device}_3_tips',
        size: size,
        build: (e) => over(
          e,
          TipsSheet(products: e.products),
        ),
      );
      await capture(
        tester,
        name: '${device}_4_thanks',
        size: size,
        storage: thanksStorage,
        build: (e) => over(
          e,
          const ThanksOverlay(
            productId: 'tip.pizza',
            tally: {'tip.coffee': 3, 'tip.pizza': 2},
            autoDismiss: false,
            onDone: null,
          ),
          scrim: const Color(0xD603060C),
        ),
      );
      await capture(
        tester,
        name: '${device}_5_member',
        size: size,
        storage: memberStorage,
        build: settings,
      );
    });
  }
}
