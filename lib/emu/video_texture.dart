// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';

import 'package:flutter/services.dart';

/// Name shared with the Linux and Windows runners.
const String videoChannelName = 'ezcore/video';

/// Access to the native frame texture on the desktop targets.
///
/// The runtime keeps the frames; this channel only hands Flutter the texture
/// identifier and tells the runner that a new core frame is ready. On other
/// targets the player keeps its existing image-based presentation.
class DesktopVideoTexture {
  DesktopVideoTexture({MethodChannel? channel, bool? isDesktop})
      : _channel = channel ?? const MethodChannel(videoChannelName),
        _isDesktop = isDesktop ?? (Platform.isLinux || Platform.isWindows);

  final MethodChannel _channel;
  final bool _isDesktop;
  int? _textureId;

  int? get textureId => _textureId;
  bool get available => _isDesktop;

  /// Registers the session with the runner and returns the texture identifier.
  /// Returns null when the native side is unavailable; presentation then
  /// falls back to decoded frames.
  Future<int?> open(int sessionAddress) async {
    if (!_isDesktop || sessionAddress == 0) return null;
    try {
      final attached = await _channel.invokeMethod<bool>(
            'attach',
            sessionAddress,
          ) ??
          false;
      if (!attached) return null;
      final id = await _channel.invokeMethod<int>('create');
      if (id == null || id < 0) return null;
      _textureId = id;
      return id;
    } on Object {
      // No channel binding, no runner, or a rejected call: keep decoding
      // frames in Dart instead of interrupting the player.
      return null;
    }
  }

  /// Publishes the latest runtime frame and marks the texture dirty.
  Future<bool> frameReady() async {
    if (_textureId == null) return false;
    try {
      return await _channel.invokeMethod<bool>('frameReady') ?? false;
    } on Object {
      return false;
    }
  }

  /// Frame counters from the native bridge, for the player's diagnostics.
  Future<Map<String, int>?> stats() async {
    if (_textureId == null) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('stats');
      if (raw == null) return null;
      return raw.map((key, value) => MapEntry(key.toString(), value as int));
    } on Object {
      return null;
    }
  }
}
