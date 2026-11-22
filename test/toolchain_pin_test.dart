// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every build leg has to use the same compiler versions. A second NDK number
/// means a core can be rebuilt with a different toolchain from the app that
/// ships it, so these gates keep one pin and wire every entry point to it.
const _pinFile = 'toolchain.json';

const _requiredKeys = <String>[
  'flutter',
  'dart',
  'ndk',
  'cmake',
  'xcode_minimum',
  'mingw',
  'llvm_mingw',
  'msvc',
];

final _ndkLiteral = RegExp(r'2[78]\.[0-9]+\.[0-9]{5,}');

bool _isGenerated(String path) {
  final parts = path.split(Platform.pathSeparator);
  return parts.any(
    (part) =>
        part == '.git' ||
        part == '.dart_tool' ||
        part == 'build' ||
        part.startsWith('build-') ||
        part == 'ephemeral' ||
        part == '.plugin_symlinks' ||
        part == '.cxx' ||
        part == 'native',
  );
}

void main() {
  group('one toolchain pin', () {
    late Map<String, dynamic> pin;

    setUpAll(() {
      final file = File(_pinFile);
      pin = file.existsSync()
          ? jsonDecode(file.readAsStringSync()) as Map<String, dynamic>
          : <String, dynamic>{};
    });

    test('records every component the build legs need', () {
      for (final key in _requiredKeys) {
        expect(pin[key], isA<String>(), reason: '$_pinFile must pin $key');
        expect(
          (pin[key] as String?)?.trim(),
          isNotEmpty,
          reason: '$_pinFile must give $key a version',
        );
      }
    });

    test('the NDK version appears only in the pin file', () {
      final offenders = <String>[];
      for (final entity in Directory('.').listSync(recursive: true)) {
        if (entity is! File) continue;
        if (_isGenerated(entity.path)) continue;
        if (entity.uri.pathSegments.last == _pinFile) continue;
        if (entity.lengthSync() > 2 * 1024 * 1024) continue;
        final text = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
        if (_ndkLiteral.hasMatch(text)) offenders.add(entity.path);
      }
      expect(
        offenders,
        isEmpty,
        reason: 'hard-coded NDK version outside $_pinFile: $offenders',
      );
    });

    test('every build entry point reads the pin', () {
      const entryPoints = <String>[
        'scripts/core_platform.sh',
        'android/app/build.gradle.kts',
        '.github/workflows/ci.yml',
        '.github/workflows/matrix.yml',
        '.github/workflows/release.yml',
        'ios/ci_scripts/ci_post_clone.sh',
      ];
      for (final path in entryPoints) {
        expect(
          File(path).readAsStringSync(),
          contains(_pinFile),
          reason: '$path must read $_pinFile',
        );
      }
    });
  });
}
