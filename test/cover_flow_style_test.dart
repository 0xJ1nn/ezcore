import 'package:ezcore/theme/cover_flow_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoverFlowStyle', () {
    test('unknown saved preferences use the safe classic preset', () {
      expect(CoverFlowStyle.fromSetting(null), CoverFlowStyle.classic);
      expect(CoverFlowStyle.fromSetting('old-value'), CoverFlowStyle.classic);
    });

    test('presets progressively reduce depth and settle time', () {
      expect(
        CoverFlowStyle.classic.rotationDegrees,
        greaterThan(CoverFlowStyle.gentle.rotationDegrees),
      );
      expect(
        CoverFlowStyle.gentle.rotationDegrees,
        greaterThan(CoverFlowStyle.flat.rotationDegrees),
      );
      expect(
        CoverFlowStyle.classic.settleDuration,
        greaterThan(CoverFlowStyle.flat.settleDuration),
      );
    });
  });
}
