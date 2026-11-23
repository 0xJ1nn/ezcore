// SPDX-License-Identifier: GPL-3.0-only WITH LicenseRef-ezCORE-core-module-exception

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Android video texture: a Flutter `SurfaceProducer` registered by the
/// platform side, whose `ANativeWindow` the runtime writes into. Only the
/// texture id crosses into Dart; every frame stays on the native side.
///
/// [create] is a no-op on other targets, where the player keeps decoding the
/// worker's RGBA packet into an image. A failure to create the texture is
/// reported through [error] so the player can fall back to that path.
class VideoTextureController {
  VideoTextureController({MethodChannel? channel, bool? enabled})
      : _channel = channel ?? const MethodChannel('ezcore/video'),
        _enabled = enabled ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _enabled;

  int? _textureId;
  int? _window;
  int _framesPresented = 0;
  String? error;

  int? get textureId => _textureId;
  int? get window => _window;
  int get framesPresented => _framesPresented;
  bool get active => _textureId != null && error == null;

  Future<void> create(int width, int height) async {
    if (!_enabled) return;
    try {
      final reply = await _channel.invokeMapMethod<String, Object?>('create', {
        'width': width,
        'height': height,
      });
      final id = reply?['textureId'];
      final handle = reply?['window'];
      if (id is! int || handle is! int || id < 0 || handle == 0) {
        error = 'Video texture unavailable';
        return;
      }
      _textureId = id;
      _window = handle;
      _framesPresented = 0;
      error = null;
    } catch (e) {
      error = 'Video texture unavailable: $e';
    }
  }

  /// The runtime has written a new frame into the window. Tell Flutter to
  /// composite it; the pixels never leave the native side.
  Future<void> markFrame() async {
    if (!active) return;
    _framesPresented++;
    try {
      await _channel.invokeMethod<void>('frameReady', {
        'textureId': _textureId,
        'frame': _framesPresented,
      });
    } catch (e) {
      error = 'Video texture stopped: $e';
    }
  }

  Future<void> release() async {
    if (!_enabled) return;
    final id = _textureId;
    _textureId = null;
    _window = null;
    if (id == null) return;
    try {
      await _channel.invokeMethod<void>('release', {'textureId': id});
    } catch (_) {
      // The activity may already be gone; the producer releases it too.
    }
  }

  /// The widget that samples the surface, or null when no texture exists.
  Widget? view({Key? key}) {
    final id = _textureId;
    if (id == null) return null;
    return Texture(
      key: key,
      textureId: id,
      filterQuality: FilterQuality.none,
    );
  }
}

/// Frame-time recorder for the player HUD and the test log. Mirrors the
/// percentiles the native run thread publishes so the two paths can be
/// compared on the same scale; the native loop's statistics replace this
/// recorder when the player switches to that thread.
class FrameStats {
  FrameStats({this.capacity = 256});

  final int capacity;
  final List<double> _samples = <double>[];
  int _cursor = 0;
  double _sumMs = 0;

  int get count => _samples.length;

  double get meanMs => count == 0 ? 0 : _sumMs / count;

  void sample(Duration elapsed) {
    final ms = elapsed.inMicroseconds / 1000.0;
    if (ms < 0 || ms > 10000) return;
    if (_samples.length < capacity) {
      _samples.add(ms);
    } else {
      _sumMs -= _samples[_cursor];
      _samples[_cursor] = ms;
      _cursor = (_cursor + 1) % capacity;
    }
    _sumMs += ms;
  }

  double _percentile(double fraction) {
    if (count == 0) return 0;
    final sorted = List<double>.from(_samples)..sort();
    final index = math.min(
      sorted.length - 1,
      math.max(0, (sorted.length * fraction).ceil() - 1),
    );
    return sorted[index];
  }

  double get p50Ms => _percentile(0.50);
  double get p95Ms => _percentile(0.95);
  double get p99Ms => _percentile(0.99);
  double get maxMs {
    var max = 0.0;
    for (final value in _samples) {
      if (value > max) max = value;
    }
    return max;
  }

  @override
  String toString() => 'frames=$count mean=${meanMs.toStringAsFixed(2)}ms '
      'p50=${p50Ms.toStringAsFixed(2)}ms p95=${p95Ms.toStringAsFixed(2)}ms '
      'p99=${p99Ms.toStringAsFixed(2)}ms max=${maxMs.toStringAsFixed(2)}ms';
}
