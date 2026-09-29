// Proves scripts/android-stubs/librt.so is real and load-bearing, rather than
// a plausible-looking file that happens to sit in the tree.
//
// Why this matters: the stub exists only to satisfy `-lrt` for cores whose
// Makefile links it unconditionally (native/src/beetle-pce/Makefile:80 and
// four other lines). Android's bionic has no librt, so if the stub were
// malformed the failure would surface as a confusing link error during a
// release build on a machine that is not this one — the worst place to find
// out. These checks run in CI and in the ordinary suite instead.
//
// The link test uses a RENAMED copy of the stub (`-lmyrt`) on purpose. Linking
// the real `-lrt` here would prove nothing: this host has glibc's own
// librt.a, which the linker finds before it ever consults LIBRARY_PATH, so the
// stub would never be exercised. Renaming removes the host library from the
// picture and leaves the stub as the only thing that can satisfy `-l`.
//
// Standard library only; skipped where no C compiler is available.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Detected at load time on purpose: the `skip:` arguments below are evaluated
/// before `setUpAll` runs, so a `late` compiler field would be uninitialised
/// there and throw instead of skipping.
String? _findCompiler() {
  for (final candidate in ['cc', 'gcc', 'clang']) {
    if (Process.runSync(candidate, ['--version']).exitCode == 0) {
      return candidate;
    }
  }
  return null;
}

void main() {
  final stub = File('scripts/android-stubs/librt.so');
  final cc = _findCompiler();
  final noCompiler = cc == null ? 'no C compiler available' : null;

  test('the librt stub exists', () {
    expect(
      stub.existsSync(),
      isTrue,
      reason: 'scripts/android-stubs/librt.so is missing. build_core.sh:299 '
          'puts this directory on LIBRARY_PATH for android builds, so without '
          'it every core whose Makefile links -lrt (cardcon, and any other '
          'core that copies that pattern) fails to build for Android.',
    );
  });

  test('the librt stub is a linker script, not an object file', () {
    // An ELF object would be a red flag: it could shadow a real libc symbol.
    // The stub must be a GNU ld INPUT() script that adds no definitions.
    final bytes = stub.readAsBytesSync();
    final head = String.fromCharCodes(bytes.take(16));
    expect(
      head.startsWith('\u{1f}ELF'),
      isFalse,
      reason: 'the stub must be a text linker script. An ELF object here '
          'risks shadowing a real libc symbol.',
    );
    expect(
      head.trimLeft().startsWith('/*'),
      isTrue,
      reason: 'expected the explanatory comment at the top of the script',
    );
  });

  test('the librt stub declares INPUT(-lc) so real symbols still resolve', () {
    // INPUT(-lc) is the safety argument: the stub satisfies the NAME `-lrt`
    // and contributes no definitions of its own, so clock_gettime and friends
    // still come from bionic's libc. A stub that defined those symbols would
    // silently override the real implementations.
    final text = stub.readAsStringSync();
    expect(
      text,
      contains('INPUT(-lc)'),
      reason: 'without INPUT(-lc) the stub would satisfy the link but leave '
          'real libc symbols unresolved',
    );
  });

  group('link behaviour', () {
    late Directory tmp;

    setUpAll(() {
      tmp = Directory.systemTemp.createTempSync('ezcore_librt_stub');
    });

    tearDownAll(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('a renamed copy satisfies -l and still resolves libc symbols', () {
      // Rename so the host's real librt cannot satisfy the flag first.
      final renamed = File('${tmp.path}/libmyrt.so');
      stub.copySync(renamed.path);

      final src = File('${tmp.path}/main.c')
        ..writeAsStringSync('''
#include <time.h>
#include <stdio.h>
int main(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  printf("%ld", (long)ts.tv_sec);
  return 0;
}
''');

      final out = '${tmp.path}/a.out';
      final build = Process.runSync(
        cc!,
        [src.path, '-o', out, '-L${tmp.path}', '-lmyrt'],
      );
      expect(
        build.exitCode,
        0,
        reason: 'the stub should satisfy -lmyrt and clock_gettime should '
            'resolve from libc.\nstderr: ${build.stderr}',
      );

      // It must be a runnable binary, not just a linkable one.
      final run = Process.runSync(out, []);
      expect(run.exitCode, 0, reason: 'linked binary failed to run');
      expect(run.stdout, isNotEmpty);
    }, skip: noCompiler);

    test('without the stub the same link fails — the stub is load-bearing', () {
      // Negative control. If this ever PASSES, something else on the system
      // is satisfying -lmyrt and the positive test above is not testing the
      // stub at all.
      final src = File('${tmp.path}/neg.c')
        ..writeAsStringSync('int main(void){return 0;}');
      final empty = Directory('${tmp.path}/empty')..createSync(recursive: true);
      final link = Process.runSync(
        cc!,
        [src.path, '-o', '${tmp.path}/neg.out', '-L${empty.path}', '-lmyrt'],
      );
      expect(
        link.exitCode,
        isNonZero,
        reason: 'a link with no stub should fail to find -lmyrt; if it '
            'succeeded, the positive test is not exercising the stub',
      );
    }, skip: noCompiler);
  });
}
