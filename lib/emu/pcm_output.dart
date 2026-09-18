import 'dart:io';

import 'package:flutter/services.dart';

import 'pcm_linux.dart';
import 'pcm_windows.dart';

abstract interface class PcmOutput {
  Future<void> start(double sampleRate);
  Future<void> write(Uint8List stereoS16);
  Future<void> stop();

  /// Human-readable sink label for Settings → Audio (e.g. "ALSA (Linux)").
  String get sinkName;
}

/// Platform factory. Mobile + macOS go through the native `ezcore/audio`
/// method channel (sinks live in each Runner); Linux uses ALSA and Windows
/// uses waveOut, both over dart:ffi with no plugins.
PcmOutput createPlatformPcm() {
  if (Platform.isLinux) return AlsaPcmOutput();
  if (Platform.isWindows) return WinmmPcmOutput();
  return PlatformPcmOutput();
}

/// Platform implementations consume signed-16 little-endian interleaved stereo.
/// Missing implementations throw; callers must show audio unavailable.
class PlatformPcmOutput implements PcmOutput {
  static const _channel = MethodChannel('ezcore/audio');

  @override
  String get sinkName {
    if (Platform.isMacOS) return 'AVAudioEngine (macOS)';
    if (Platform.isIOS) return 'AVAudioEngine (iOS)';
    if (Platform.isAndroid) return 'AudioTrack (Android)';
    return 'Native channel sink';
  }

  @override
  Future<void> start(double sampleRate) =>
      _channel.invokeMethod<void>('start', {'sampleRate': sampleRate});
  @override
  Future<void> write(Uint8List stereoS16) async {
    if (stereoS16.length % 4 != 0) throw ArgumentError('Incomplete stereo PCM');
    if (stereoS16.isNotEmpty) {
      await _channel.invokeMethod<void>('write', stereoS16);
    }
  }

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
