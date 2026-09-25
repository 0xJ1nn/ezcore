import 'package:ezcore/theme/layout.dart';
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The five layout families are the contract every screen relies on, so
/// they get their own test: if these drift, every screen drifts with them.
void main() {
  group('Layout.ofSize', () {
    // Studio-plate viewports: the five frames the design is drawn for.
    test('desktop window', () {
      expect(
        Layout.ofSize(const Size(1600, 1000), Orientation.landscape),
        OrbitLayout.desktop,
      );
    });

    test('tablet landscape', () {
      expect(
        Layout.ofSize(const Size(1024, 768), Orientation.landscape),
        OrbitLayout.tablet,
      );
    });

    test('phone landscape stays a phone even though it is wide', () {
      expect(
        Layout.ofSize(const Size(844, 390), Orientation.landscape),
        OrbitLayout.phoneLandscape,
      );
    });

    test('phone portrait', () {
      expect(
        Layout.ofSize(const Size(390, 844), Orientation.portrait),
        OrbitLayout.phonePortrait,
      );
    });

    test('a tall tablet in portrait is not treated as a phone', () {
      expect(
        Layout.ofSize(const Size(834, 1194), Orientation.portrait),
        OrbitLayout.tabletPortrait,
      );
      expect(
        Layout.ofSize(const Size(834, 1194), Orientation.landscape),
        OrbitLayout.tablet,
      );
    });

    test('breakpoints are inclusive on the lower edge', () {
      // Exactly 700 wide, landscape: first rail / non-compact layout.
      expect(
        Layout.ofSize(const Size(Tokens.bpCompact, 900), Orientation.landscape),
        OrbitLayout.tablet,
      );
      // Exactly 1180 wide: first desktop.
      expect(
        Layout.ofSize(const Size(Tokens.bpDesktop, 900), Orientation.landscape),
        OrbitLayout.desktop,
      );
    });

    test('a short landscape window is compressed however wide it is', () {
      // Height is the scarce axis: a 1200x600 window cannot carry the
      // desktop rhythm either.
      expect(
        Layout.ofSize(const Size(1200, 600), Orientation.landscape),
        OrbitLayout.phoneLandscape,
      );
    });
  });

  group('layout capabilities', () {
    test('only phone portrait drops the rail for a bottom bar', () {
      expect(Layout.hasRail(OrbitLayout.phonePortrait), isFalse);
      expect(Layout.hasBottomBar(OrbitLayout.phonePortrait), isTrue);
      for (final l in [
        OrbitLayout.desktop,
        OrbitLayout.tablet,
        OrbitLayout.tabletPortrait,
        OrbitLayout.phoneLandscape,
      ]) {
        expect(Layout.hasRail(l), isTrue, reason: Layout.label(l));
        expect(Layout.hasBottomBar(l), isFalse, reason: Layout.label(l));
      }
    });

    test('phone families are exactly the two phone shapes', () {
      expect(Layout.isPhone(OrbitLayout.phonePortrait), isTrue);
      expect(Layout.isPhone(OrbitLayout.phoneLandscape), isTrue);
      expect(Layout.isPhone(OrbitLayout.tabletPortrait), isFalse);
      expect(Layout.isPhone(OrbitLayout.tablet), isFalse);
      expect(Layout.isPhone(OrbitLayout.desktop), isFalse);
    });

    test('short layouts are the compressed ones', () {
      expect(Layout.isShort(OrbitLayout.phoneLandscape), isTrue);
      expect(Layout.isShort(OrbitLayout.tablet), isTrue);
      expect(Layout.isShort(OrbitLayout.desktop), isFalse);
      expect(Layout.isShort(OrbitLayout.phonePortrait), isFalse);
      expect(Layout.isShort(OrbitLayout.tabletPortrait), isFalse);
    });
  });
}
