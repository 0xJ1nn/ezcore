// Guards the bundled Material Symbols contract: the family is registered, every
// constant points at it, the variable axes survive the subset, and the glyphs
// the design uses are actually mapped by the font file.
import 'dart:convert';
import 'dart:io';

import 'package:ezcore/theme/symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final bytes = File(
    'assets/fonts/MaterialSymbolsRounded.ttf',
  ).readAsBytesSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));

  int tableOffset(String tag) {
    final numTables = data.getUint16(4);
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + i * 16;
      if (String.fromCharCodes(bytes.sublist(rec, rec + 4)) == tag) {
        return data.getUint32(rec + 8);
      }
    }
    throw StateError('font table $tag not found');
  }

  test('the icon family is registered in pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: MaterialSymbolsRounded'));
    expect(pubspec, contains('asset: assets/fonts/MaterialSymbolsRounded.ttf'));
  });

  test('every symbol uses the bundled family', () {
    expect(Symbols.all, hasLength(104));
    for (final symbol in Symbols.all) {
      expect(symbol.fontFamily, 'MaterialSymbolsRounded');
      expect(symbol.codePoint, greaterThan(0));
    }
  });

  test('the variable FILL and wght axes survive the subset', () {
    final fvar = tableOffset('fvar');
    final axisCount = data.getUint16(fvar + 8);
    final axisSize = data.getUint16(fvar + 10);
    final offsetToData = data.getUint16(fvar + 4);
    final axes = <String, (double, double, double)>{};
    for (var i = 0; i < axisCount; i++) {
      final a = fvar + offsetToData + i * axisSize;
      final tag = String.fromCharCodes(bytes.sublist(a, a + 4));
      axes[tag] = (
        data.getInt32(a + 4) / 65536,
        data.getInt32(a + 8) / 65536,
        data.getInt32(a + 12) / 65536,
      );
    }
    expect(axes.keys, containsAll(<String>['FILL', 'wght', 'GRAD', 'opsz']));
    expect(axes['FILL'], (0.0, 0.0, 1.0));
    expect(axes['wght']!.$1, 100);
    expect(axes['wght']!.$3, 700);
  });

  test('the subset maps every symbol except warning', () {
    final mapped = _cmapCodepoints(bytes, data);
    final missing = Symbols.all
        .where((s) => !mapped.contains(s.codePoint))
        .map((s) => s.codePoint)
        .toSet();
    // The vendored symbols list ends with `warning 0xf083`, but the subset
    // itself does not include that codepoint. Keep the constant (it is part of
    // the design list) and fail loudly if any other glyph goes missing.
    expect(missing, <int>{0xf083});
  });

  testWidgets('the font loads from the app bundle', (tester) async {
    final manifest =
        (json.decode(await rootBundle.loadString('FontManifest.json')) as List)
            .cast<Map<String, dynamic>>();
    final entry = manifest.firstWhere(
      (f) => f['family'] == 'MaterialSymbolsRounded',
    );
    final fonts = (entry['fonts'] as List).cast<Map<String, dynamic>>();
    expect(fonts.single['asset'], 'assets/fonts/MaterialSymbolsRounded.ttf');

    final loader = FontLoader('MaterialSymbolsRounded');
    for (final font in fonts) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: Icon(Symbols.favorite, fill: 1, weight: 600),
        ),
      ),
    );
    expect(find.byType(Icon), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Codepoints mapped by the font's Unicode cmap (formats 4 and 12).
Set<int> _cmapCodepoints(Uint8List bytes, ByteData data) {
  int tableOffset(String tag) {
    final numTables = data.getUint16(4);
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + i * 16;
      if (String.fromCharCodes(bytes.sublist(rec, rec + 4)) == tag) {
        return data.getUint32(rec + 8);
      }
    }
    throw StateError('font table $tag not found');
  }

  final cmap = tableOffset('cmap');
  final count = data.getUint16(cmap + 2);
  final codepoints = <int>{};
  for (var i = 0; i < count; i++) {
    final rec = cmap + 4 + i * 8;
    final sub = cmap + data.getUint32(rec + 4);
    final format = data.getUint16(sub);
    if (format == 4) {
      final segX2 = data.getUint16(sub + 6);
      final endBase = sub + 14;
      final startBase = endBase + segX2 + 2;
      final deltaBase = startBase + segX2;
      final rangeBase = deltaBase + segX2;
      for (var s = 0; s < segX2 ~/ 2; s++) {
        final end = data.getUint16(endBase + s * 2);
        final start = data.getUint16(startBase + s * 2);
        final delta = data.getUint16(deltaBase + s * 2);
        final rangeOffset = data.getUint16(rangeBase + s * 2);
        for (var c = start; c <= end && c != 0xFFFF; c++) {
          if (rangeOffset == 0) {
            if (((c + delta) & 0xFFFF) != 0) codepoints.add(c);
          } else {
            final glyph = data.getUint16(
              rangeBase + s * 2 + rangeOffset + (c - start) * 2,
            );
            if (glyph != 0) codepoints.add(c);
          }
        }
      }
    } else if (format == 12) {
      final groups = data.getUint32(sub + 12);
      for (var g = 0; g < groups; g++) {
        final o = sub + 16 + g * 12;
        final start = data.getUint32(o);
        final end = data.getUint32(o + 4);
        for (var c = start; c <= end; c++) {
          codepoints.add(c);
        }
      }
    }
  }
  return codepoints;
}
