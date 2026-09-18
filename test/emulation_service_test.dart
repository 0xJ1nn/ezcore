import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/emulation_service.dart';
import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'test_paths.dart' as paths;

String? get bridgeLib => paths.bridgeLib();
String? get synthLib => paths.synthLib();

bool get _built => bridgeLib != null && synthLib != null;

EzCoreRuntime _runtime() => EzCoreRuntime.load(runtimePath: bridgeLib!);

void main() {
  group('EmulationService lifecycle', () {
    test(
      'start with a missing core artifact throws EmulationException',
      skip: _built ? null : 'runtime/synth core not built',
      () {
        final service = EmulationService(runtime: _runtime());
        expect(
          () => service.start(
            corePath: '/nonexistent/core.dylib',
            romPath: '/nonexistent/rom.gb',
            rom: Uint8List(0),
          ),
          throwsA(isA<EmulationException>()),
        );
      },
    );

    test(
      'operations before start throw StateError',
      skip: _built ? null : 'runtime/synth core not built',
      () {
        final service = EmulationService(runtime: _runtime());
        expect(service.isRunning, isFalse);
        expect(() => service.runFrame(), throwsStateError);
        expect(() => service.frameBytes(), throwsStateError);
        expect(() => service.setButton(0, 0, true), throwsStateError);
        expect(() => service.saveState(), throwsStateError);
      },
    );

    test(
      'start loads core, inits, loads content and exposes geometry',
      skip: _built ? null : 'runtime/synth core not built',
      () async {
        final service = EmulationService(runtime: _runtime());
        await service.start(
          corePath: synthLib!,
          romPath: '/dev/null',
          rom: Uint8List(0),
        );
        try {
          expect(service.isRunning, isTrue);
          expect(service.coreName, 'ezTest Synth');
          expect(service.geometry.w, 256);
          expect(service.geometry.h, 240);
          expect(service.geometry.fps, 60.0);
          expect(service.sampleRate, 44100.0);
        } finally {
          service.close();
        }
      },
    );

    test(
      'runFrame produces real frame bytes and drainable audio',
      skip: _built ? null : 'runtime/synth core not built',
      () async {
        final service = EmulationService(runtime: _runtime());
        await service.start(
          corePath: synthLib!,
          romPath: '/dev/null',
          rom: Uint8List(0),
        );
        try {
          for (var i = 0; i < 10; i++) {
            service.runFrame();
          }
          final bytes = service.frameBytes();
          expect(bytes, isNotNull);
          expect(bytes!.length, 256 * 240 * 4);
          expect(service.frameWidth, 256);
          expect(service.frameHeight, 240);
          expect(service.audioPending, greaterThan(0));
          final out = BytesBuilder();
          final drained = service.drainAudio(1024, out);
          expect(drained, greaterThan(0));
          expect(out.length, drained * 4);
        } finally {
          service.close();
        }
      },
    );

    test(
      'save state round trip and reset work while running',
      skip: _built ? null : 'runtime/synth core not built',
      () async {
        final service = EmulationService(runtime: _runtime());
        await service.start(
          corePath: synthLib!,
          romPath: '/dev/null',
          rom: Uint8List(0),
        );
        try {
          for (var i = 0; i < 5; i++) {
            service.runFrame();
          }
          final snap = service.saveState();
          expect(snap, isNotNull);
          expect(snap!.length, greaterThan(0));
          service.reset();
          service.runFrame();
          expect(service.loadState(snap), isTrue);
        } finally {
          service.close();
        }
      },
    );

    test(
      'close unloads the session; double close and post-close ops behave',
      skip: _built ? null : 'runtime/synth core not built',
      () async {
        final service = EmulationService(runtime: _runtime());
        await service.start(
          corePath: synthLib!,
          romPath: '/dev/null',
          rom: Uint8List(0),
        );
        expect(service.isRunning, isTrue);
        service.close();
        expect(service.isRunning, isFalse);
        service.close(); // idempotent
        expect(() => service.runFrame(), throwsStateError);
      },
    );
  });
}
