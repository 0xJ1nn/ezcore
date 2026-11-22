// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

// The in-app logos are the exported brand files, rendered into Flutter's
// density buckets by scripts/render_icons.sh.
import 'package:ezcore/brand/brand_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Image> pumpLogo(WidgetTester t, Widget logo) async {
    await t.pumpWidget(
      Directionality(textDirection: TextDirection.ltr, child: logo),
    );
    final image = t.widget<Image>(find.byType(Image));
    expect(image.image, isA<AssetImage>());
    expect(image.filterQuality, FilterQuality.medium);
    expect(find.bySemanticsLabel('ezCORE'), findsOneWidget);
    expect(t.takeException(), isNull);
    return image;
  }

  testWidgets('the mark shows the exported mark at its requested height', (
    t,
  ) async {
    final image = await pumpLogo(t, const BrandMark(height: 40));
    expect((image.image as AssetImage).assetName, 'assets/branding/inapp/mark.png');
    expect(image.height, 40);
  });

  testWidgets('the wordmark shows the exported wordmark at its height', (
    t,
  ) async {
    final image = await pumpLogo(t, const BrandWordmark(height: 20));
    expect(
      (image.image as AssetImage).assetName,
      'assets/branding/inapp/wordmark.png',
    );
    expect(image.height, 20);
  });

  testWidgets('the lockup shows the exported lockup at its height', (t) async {
    final image = await pumpLogo(t, const BrandLockup(height: 30));
    expect(
      (image.image as AssetImage).assetName,
      'assets/branding/inapp/lockup.png',
    );
    expect(image.height, 30);
  });
}
