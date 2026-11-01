// Locks the Orbit token contract: colours, radii, type roles, motion,
// elevation and button states. Screens may change; these values may not
// drift without updating the design spec and this test.
import 'package:ezcore/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// The legacy aliases are intentionally exercised below.
// ignore_for_file: deprecated_member_use

void main() {
  group('colour', () {
    test('new Orbit colours are exact', () {
      expect(Tokens.warn, const Color(0xFFFFC46B));
      expect(Tokens.focusHalo, const Color(0x3D007BFF));
      expect(Tokens.iconBlue, const Color(0xFF4DA3FF));
      expect(Tokens.toastBg, const Color(0xFF14202F));
      expect(Tokens.dangerText, const Color(0xFFFF8A80));
    });

    test('core palette is unchanged', () {
      expect(Tokens.bg, const Color(0xFF060B14));
      expect(Tokens.text, const Color(0xFFDDE6F4));
      expect(Tokens.muted, const Color(0xFF9AA8BC));
      expect(Tokens.accent, const Color(0xFF007BFF));
      expect(Tokens.accentHi, const Color(0xFF0086FF));
      expect(Tokens.accentDeep, const Color(0xFF0065ED));
      expect(Tokens.ok, const Color(0xFF7DE89A));
      expect(Tokens.danger, const Color(0xFFFF6B5E));
    });
  });

  group('spacing and radii', () {
    test('Orbit spacing scale', () {
      expect(Tokens.s1, 4);
      expect(Tokens.s2, 8);
      expect(Tokens.s3, 12);
      expect(Tokens.s4, 16);
      expect(Tokens.s5, 24);
      expect(Tokens.s6, 32);
      expect(Tokens.s7, 44);
      expect(Tokens.s8, 64);
      expect(Tokens.pad, Tokens.s4);
    });

    test('changed radii match the handoff', () {
      expect(Tokens.radiusCover, 6, reason: 'was 5');
      expect(Tokens.radiusDock, 20, reason: 'was 18');
      expect(Tokens.radiusDialog, 22, reason: 'was 10');
      expect(Tokens.radiusLg, 22);
      expect(Tokens.radiusPrimary, 12);
      expect(Tokens.radiusMd, 14);
      expect(Tokens.radiusSheet, 24);
      expect(Tokens.radiusPill, 999);
      expect(Tokens.radiusToast, 999);
    });

    test('rail is 104 wide', () {
      expect(Tokens.rail, 104, reason: 'was 112');
      expect(Tokens.railShort, 72);
    });
  });

  group('motion', () {
    test('durations', () {
      expect(Tokens.instantDur.inMilliseconds, 120);
      expect(Tokens.fastDur.inMilliseconds, 200);
      expect(Tokens.baseDur.inMilliseconds, 320);
      expect(Tokens.moveDur.inMilliseconds, 540);
      expect(Tokens.ambientDur.inMilliseconds, 650);
      expect(Tokens.sceneDur.inMilliseconds, 1100);
      expect(Tokens.easeDur, Tokens.ambientDur);
    });

    test('easeInOut is the in-out curve', () {
      const expected = Cubic(0.65, 0, 0.35, 1);
      for (final t in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(
          Tokens.easeInOut.transform(t),
          closeTo(expected.transform(t), 1e-9),
        );
      }
    });
  });

  group('type roles', () {
    test('display roles', () {
      expect(Tokens.displayHero.fontSize, 76);
      expect(Tokens.displayHero.fontWeight, FontWeight.w700);
      expect(Tokens.displayHero.height, 0.95);
      expect(Tokens.displayHero.letterSpacing, closeTo(-2.66, 1e-9));

      expect(Tokens.displayScreen.fontSize, 44);
      expect(Tokens.displayScreen.fontWeight, FontWeight.w600);
      expect(Tokens.displayScreen.height, 1);
      expect(Tokens.displayScreen.letterSpacing, closeTo(-1.32, 1e-9));

      expect(Tokens.displayDock.fontSize, 32);
      expect(Tokens.displayDock.letterSpacing, closeTo(-0.64, 1e-9));

      expect(Tokens.displayPanel.fontSize, 26);
      expect(Tokens.displayPanel.height, 1.1);
      expect(Tokens.displayPanel.letterSpacing, closeTo(-0.52, 1e-9));

      expect(Tokens.displayDialog.fontSize, 28);
    });

    test('section, eyebrow and body roles', () {
      expect(Tokens.sectionTitle.fontSize, 19);
      expect(Tokens.sectionTitle.fontWeight, FontWeight.w600);
      expect(Tokens.sectionTitle.letterSpacing, closeTo(-0.19, 1e-9));

      expect(Tokens.eyebrow.fontSize, 13);
      expect(Tokens.eyebrow.fontWeight, FontWeight.w500);
      expect(Tokens.eyebrow.letterSpacing, closeTo(3.9, 1e-9));
      expect(Tokens.eyebrow.color, Tokens.iconBlue);

      expect(Tokens.bodyBase.fontSize, 14);
      expect(Tokens.bodyBase.fontWeight, FontWeight.w500);
      expect(Tokens.bodyBase.height, 1.5);

      expect(Tokens.labelMin.fontSize, 12.5);
      expect(Tokens.labelMin.fontWeight, FontWeight.w600);

      expect(Tokens.bodyAction.fontSize, 17);
      expect(Tokens.bodyActionDock.fontSize, 16);
      expect(Tokens.bodyLead.fontSize, 16);
      expect(Tokens.bodyLead.height, 1.6);
    });

    test('stat, system and glyph roles', () {
      expect(Tokens.statLabel.fontSize, 12);
      expect(Tokens.statLabel.letterSpacing, closeTo(0.96, 1e-9));
      expect(Tokens.statValue.fontSize, 19);
      expect(Tokens.statValue.fontFamily, Tokens.displayFamily);

      expect(Tokens.systemLabel.fontSize, 12);
      expect(Tokens.systemLabel.letterSpacing, closeTo(1.2, 1e-9));
      expect(Tokens.systemLabel.color, Tokens.systemLabelFg);

      expect(Tokens.glyphChip.fontSize, 12);
      expect(Tokens.glyphChip.fontWeight, FontWeight.w700);
      expect(Tokens.railFooter.letterSpacing, closeTo(2.88, 1e-9));
    });

    test('text never renders under 12 px through the helpers', () {
      expect(Tokens.display(size: 8).fontSize, 12);
      expect(Tokens.body(size: 8).fontSize, 12);
      expect(Tokens.labelMin.fontSize, greaterThanOrEqualTo(12));
    });
  });

  group('elevation', () {
    test('recessed, card, glass and modal decorations', () {
      expect(Tokens.statPanelDecor.borderRadius, BorderRadius.circular(14));
      expect(Tokens.statPanelDecor.color, const Color(0x80060A11));

      expect(Tokens.coreCardDecor.borderRadius, BorderRadius.circular(20));
      expect(Tokens.coreCardDecor.boxShadow, isNotEmpty);

      expect(Tokens.dockDecor.borderRadius, BorderRadius.circular(20));
      expect(Tokens.panelGlass, Tokens.dockDecor);

      expect(Tokens.dialogDecor.borderRadius, BorderRadius.circular(22));
      expect(Tokens.sheetDecor.borderRadius, const BorderRadius.vertical(
        top: Radius.circular(24),
      ));
    });

    test('HALO, HALO3 and RING', () {
      expect(Tokens.halo, hasLength(3));
      expect(Tokens.halo.first.color, Tokens.accent);
      expect(Tokens.halo.first.spreadRadius, 2);
      expect(Tokens.halo[1].color, Tokens.focusHalo);
      expect(Tokens.halo[1].spreadRadius, 7);

      expect(Tokens.halo3, hasLength(2));
      expect(Tokens.halo3.first.spreadRadius, 3);
      expect(Tokens.halo3[1].spreadRadius, 11);

      expect(Tokens.ring, hasLength(1));
      expect(Tokens.ringBorder.top.color, const Color(0x24DDE6F4));
    });
  });

  group('button states', () {
    test('primary fills and shadows', () {
      final rest = Tokens.primaryButton();
      expect(rest.color, Tokens.accent);
      expect(rest.boxShadow, hasLength(1));

      final hover = Tokens.primaryButton(state: OrbitButtonState.hover);
      expect(hover.color, Tokens.accentHi);
      expect(hover.boxShadow, Tokens.halo);

      final pressed = Tokens.primaryButton(state: OrbitButtonState.pressed);
      expect(pressed.color, Tokens.accentDeep);
      expect(pressed.boxShadow, Tokens.halo);

      final disabled = Tokens.primaryButton(state: OrbitButtonState.disabled);
      expect(disabled.boxShadow, isEmpty);
      expect(disabled.color!.a, closeTo(0.4, 0.01));
    });

    test('secondary fill and ring', () {
      final rest = Tokens.secondaryButton();
      expect(rest.color, const Color(0x0DDDE6F4));
      expect(rest.border, Tokens.ringBorder);
      expect(rest.boxShadow, isNull);

      final hover = Tokens.secondaryButton(state: OrbitButtonState.hover);
      expect(hover.color, const Color(0x1ADDE6F4));
      expect(hover.boxShadow, Tokens.halo);
    });
  });

  group('legacy aliases', () {
    test('old names resolve to the new roles', () {
      expect(Tokens.h1.fontSize, Tokens.displayScreen.fontSize);
      expect(Tokens.dockTitle.fontSize, Tokens.displayDock.fontSize);
      expect(Tokens.screenTitle, Tokens.displayScreen.fontSize);
      expect(Tokens.dockBodyStyle.fontSize, 14);
      expect(Tokens.footerStyle.letterSpacing, Tokens.railFooter.letterSpacing);
      expect(Tokens.pillRadius, Tokens.radiusPill);
      expect(Tokens.dockPanelRadius, Tokens.radiusDock);
    });
  });
}
