import 'dart:io';

import 'package:ezcore/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the version users see matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final version = line.split(':')[1].trim().split('+').first;
    expect(appVersion, version);
  });
}
