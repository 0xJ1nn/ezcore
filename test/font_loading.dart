// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

/// Loads the bundled fonts so widget tests measure text with the same faces
/// the app uses. Cover titles are balanced with [TextPainter], whose result
/// depends on real glyph metrics; the test binding's default face has 1-em
/// glyphs and would otherwise wrap every title differently from the app.
library;

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadBundledFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final fam in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(fam['family'] as String);
    for (final f in (fam['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(f['asset'] as String));
    }
    await loader.load();
  }
}
