import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ezcore/emu/core_session_backend.dart';
import 'package:ezcore/emu/player_controller.dart';
import 'package:ezcore/emu/pcm_output.dart';
import 'package:ezcore/emu/video_texture.dart';
import 'package:ezcore/main.dart';
import 'package:ezcore/state/app_state.dart';

// Local acceptance harness. No ROM or core is bundled by this test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real import to native player, pause and save/load', (
    tester,
  ) async {
    const checkout = String.fromEnvironment('EZCORE_TEST_CHECKOUT');
    if (checkout.isEmpty) {
      markTestSkipped('Pass --dart-define=EZCORE_TEST_CHECKOUT=/checkout');
      return;
    }
    final state = AppState.ephemeral();
    await state.setSetting('coreDirectory', '$checkout/native/cores');
    await state.load();
    expect(
      state.registry.isInstalled('mgba'),
      isTrue,
      reason:
          'Discovery failed: ${state.loadError}; ${state.coreDiscoveryErrors}',
    );
    await tester.pumpWidget(MaterialApp(home: Shell(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add games').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      '$checkout/native/test-roms/test.gba',
    );
    await tester.tap(find.text('Scan'));
    for (
      var i = 0;
      i < 100 && find.text('Import scanned content').evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('Import scanned content'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .join(' | '),
    );
    await tester.tap(find.text('Import scanned content'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('test.gba'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play'));
    for (
      var i = 0;
      i < 100 &&
          find.byType(RawImage).evaluate().isEmpty &&
          find.byType(Texture).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (Platform.isAndroid) {
      expect(find.byType(Texture), findsOneWidget);
    } else {
      expect(find.byType(RawImage), findsOneWidget);
      expect(
        tester.widget<RawImage>(find.byType(RawImage)).image!.width,
        240,
      );
    }
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.byTooltip('Quick-save'));
    await tester.pump(const Duration(seconds: 1));
    expect(
      await state.saves.download(state.games.single.id, 'slot0'),
      isNotEmpty,
    );
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load state — slot 0'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('State loaded'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });

  // The texture path needs no core or ROM: a synthetic backend hands the real
  // PlayerController a presented frame every tick. This is the Android-emulator
  // half of the video texture bridge acceptance criteria.
  testWidgets('android texture presents a synthetic core at 60 fps', (
    tester,
  ) async {
    if (!Platform.isAndroid) {
      markTestSkipped('SurfaceProducer texture is an Android bridge');
      return;
    }
    final backend = _SyntheticBackend();
    final video = VideoTextureController(enabled: true);
    final player = PlayerController(audio: _SilentAudio(), video: video)
      ..useBackend(backend);
    final logs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    try {
      await player.open(
        runtimeRef: const {'kind': 'process'},
        corePath: 'synthetic',
        contentPath: 'synthetic',
        systemDir: '',
        saveDir: '',
      );
      await tester.pumpWidget(
        MaterialApp(home: Center(child: SizedBox(
          width: 240,
          height: 160,
          child: video.view(),
        ))),
      );
      expect(video.textureId, isNotNull);
      expect(video.window, isNotNull);
      expect(find.byType(Texture), findsOneWidget);

      // Two seconds at 60 Hz: enough for the 120-frame stats log line.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(backend.attached, isTrue);
      expect(video.framesPresented, greaterThanOrEqualTo(100));
      expect(player.frameStats.count, greaterThanOrEqualTo(100));
      expect(
        logs.where((l) => l.contains('ezcore/video frame-time')),
        isNotEmpty,
        reason: logs.join(' | '),
      );
      expect(player.frameStats.toString(), contains('p99='));
    } finally {
      debugPrint = previousDebugPrint;
      await player.close();
      player.dispose();
    }
  });
}

class _SilentAudio implements PcmOutput {
  @override
  String get sinkName => 'test sink';
  @override
  Future<void> start(double rate) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> write(Uint8List pcm) async {}
}

/// Deterministic 240x160 core: every tick presents a frame into the surface.
class _SyntheticBackend implements CoreSessionBackend {
  int frames = 0;
  bool attached = false;

  @override
  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
    Map<String, String> coreOptions = const {},
  }) async => {
    'name': 'Synthetic',
    'width': 240,
    'height': 160,
    'fps': 60.0,
    'sampleRate': 44100.0,
    'canSave': false,
  };

  @override
  Future<Map<String, dynamic>?> frame({int count = 1}) async {
    frames += count;
    return {
      'width': 240,
      'height': 160,
      'rgba': null,
      'pcm': Uint8List(0),
      'presented': true,
    };
  }

  @override
  Future<bool> attachVideo(int window, int width, int height) async {
    attached = true;
    return true;
  }

  @override
  Future<void> pause(bool value) async {}
  @override
  Future<void> button(int id, bool pressed, {int port = 0}) async {}
  @override
  Future<void> analog(int port, int stick, int axis, int value) async {}
  @override
  Future<void> mouseMove(int dx, int dy) async {}
  @override
  Future<void> mouseButton(int id, bool pressed) async {}
  @override
  Future<void> key(int keycode, bool pressed,
      {int character = 0, int modifiers = 0}) async {}
  @override
  Future<void> pointer(int x, int y, bool pressed) async {}
  @override
  Future<Uint8List> save() async => Uint8List(0);
  @override
  Future<void> restore(Uint8List bytes) async {}
  @override
  Future<List<int>> applyCheats(List<List<Object>> cheats) async => const [];
  @override
  Future<void> reset() async {}
  @override
  Future<List<Map<String, String>>> coreOptions() async => const [];
  @override
  Future<bool> setCoreOption(String key, String value) async => false;
  @override
  Future<void> close() async {}
}
