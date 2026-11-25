// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import 'package:flutter/foundation.dart';

/// Resolves the plan requested at startup, or null when no self-check was asked
/// for. Release builds ignore every source, so the shipped app behaves the same
/// on all five targets.
String? requestedSelftestPlan({
  required bool releaseMode,
  List<String> arguments = const <String>[],
  Map<String, String> environment = const <String, String>{},
  String compileTime = '',
}) {
  if (releaseMode) return null;

  for (var i = 0; i + 1 < arguments.length; i++) {
    if (arguments[i] == '--selftest') {
      final name = arguments[i + 1];
      return name.isEmpty ? null : name;
    }
  }

  final runtime = environment['EZCORE_SELFTEST'];
  if (runtime != null && runtime.isNotEmpty) return runtime;
  return compileTime.isEmpty ? null : compileTime;
}

/// The host a self-check would run on. Injected so availability can be tested
/// without pretending to be another operating system.
class SelftestHost {
  const SelftestHost({
    required this.operatingSystem,
    required this.releaseMode,
    required this.harnessPresent,
  });

  factory SelftestHost.current(String harnessDirectory) {
    final executable = Platform.isWindows ? 'ezplay.exe' : 'ezplay';
    return SelftestHost(
      operatingSystem: Platform.operatingSystem,
      releaseMode: kReleaseMode,
      harnessPresent: File('$harnessDirectory/$executable').existsSync(),
    );
  }

  final String operatingSystem;
  final bool releaseMode;
  final bool harnessPresent;
}

class SelftestAvailability {
  const SelftestAvailability(this.available, this.reason);

  final bool available;
  final String reason;
}

/// Only a debug or profile build on a host with the native harness can run a
/// self-check. Every other case carries the reason it is unavailable.
SelftestAvailability selftestAvailability(SelftestHost host) {
  if (host.releaseMode) {
    return const SelftestAvailability(
      false,
      'Self-checks are not part of release builds on any platform.',
    );
  }
  if (host.operatingSystem != 'linux') {
    return SelftestAvailability(
      false,
      'Self-checks are unavailable on ${host.operatingSystem}.',
    );
  }
  if (!host.harnessPresent) {
    return const SelftestAvailability(
      false,
      'The native self-check harness is not available here.',
    );
  }
  return const SelftestAvailability(true, '');
}
