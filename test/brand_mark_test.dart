// The in-app logo is drawn from the generated brand paths
// (scripts/build_brand.py), in the brand files' proportions.
import 'package:ezcore/brand/brand_mark.dart';
import 'package:ezcore/brand/brand_paths.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the generated mark and wordmark have their shapes', () {
    expect(solidMarkPaths, hasLength(2)); // the two halves of the pad
    expect(wordmarkPaths.length, greaterThanOrEqualTo(7)); // e z C O R E
    for (final p in [...solidMarkPaths, ...wordmarkPaths]) {
      expect(p.getBounds().isEmpty, isFalse);
    }
    final mark = solidMarkPaths
        .map((p) => p.getBounds())
        .reduce((a, b) => a.expandToInclude(b));
    expect(mark.right, lessThanOrEqualTo(markWidth + 0.5));
    expect(mark.bottom, lessThanOrEqualTo(markHeight + 0.5));
  });

  testWidgets('mark, wordmark and lockup keep the brand proportions', (
    t,
  ) async {
    await t.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BrandMark(height: 40),
              BrandWordmark(height: 20),
              BrandLockup(height: 30),
            ],
          ),
        ),
      ),
    );
    final mark = t.getSize(find.byType(BrandMark).first);
    expect(mark.width / mark.height, closeTo(markWidth / markHeight, 0.01));
    final word = t.getSize(find.byType(BrandWordmark).first);
    expect(
      word.width / word.height,
      closeTo(wordmarkWidth / wordmarkHeight, 0.01),
    );
    expect(find.bySemanticsLabel('ezCORE'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
