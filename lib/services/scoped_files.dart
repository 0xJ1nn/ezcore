import 'dart:io';

import 'package:flutter/services.dart';

/// Access to user files outside the app sandbox.
///
/// Desktop sandboxes (macOS release) revoke filesystem access outside the
/// container: a ROM imported last week is unreadable today unless the app
/// holds a security-scoped bookmark. Saves, states, covers and staged
/// cores live inside the sandbox and never go through here.
abstract class ScopedFiles {
  /// Remembers [path] for future sessions. Best-effort: silently succeeds
  /// where bookmarks don't exist (unsandboxed desktop, mobile pickers).
  Future<void> saveBookmark(String path);

  /// Runs [fn] with read access to [path] held. Where no bookmark or
  /// channel exists, runs [fn] directly (dev runs, mobile, tests).
  Future<T> withAccess<T>(String path, Future<T> Function() fn);
}

/// macOS implementation over the `ezcore/files` Runner channel.
/// Degrades to direct execution when the channel is absent (unit tests,
/// non-macOS hosts) — never throws for missing platform support.
class MethodChannelScopedFiles implements ScopedFiles {
  MethodChannelScopedFiles({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('ezcore/files');
  final MethodChannel _channel;

  @override
  Future<void> saveBookmark(String path) async {
    try {
      await _channel.invokeMethod<bool>('saveBookmark', {'path': path});
    } catch (_) {
      // No bookmark store on this host; access needs no scoping.
    }
  }

  @override
  Future<T> withAccess<T>(String path, Future<T> Function() fn) async {
    bool held = false;
    try {
      held = await _channel.invokeMethod<bool>(
            'startAccess',
            {'path': path},
          ) ??
          false;
    } catch (_) {
      held = false;
    }
    try {
      return await fn();
    } finally {
      if (held) {
        try {
          await _channel.invokeMethod<void>('stopAccess', {'path': path});
        } catch (_) {}
      }
    }
  }
}

/// Direct execution. Used on platforms without scoped bookmarks
/// (mobile pickers grant their own access) and in tests.
class PassthroughScopedFiles implements ScopedFiles {
  const PassthroughScopedFiles();

  @override
  Future<void> saveBookmark(String path) async {}

  @override
  Future<T> withAccess<T>(String path, Future<T> Function() fn) => fn();
}

/// Platform factory: channel-backed on macOS, passthrough elsewhere.
ScopedFiles createScopedFiles() =>
    Platform.isMacOS ? MethodChannelScopedFiles() : const PassthroughScopedFiles();
