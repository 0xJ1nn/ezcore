import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../runtime/ezcore_runtime.dart';
import 'emulation_service.dart';

/// Single native-session owner. Every native call runs in this isolate.
/// Request/response frames provide backpressure: the host requests the next
/// frame only after consuming the previous video/audio packet. This is NOT
/// process isolation: a native core crash can still terminate the application.
class EmulationWorker {
  Isolate? _isolate;
  SendPort? _commands;
  bool _opening = false;

  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
  }) async {
    if (_opening || _isolate != null) throw StateError('Worker already open');
    _opening = true;
    final ready = ReceivePort();
    try {
      _isolate = await Isolate.spawn(_workerMain, ready.sendPort);
      _commands = await ready.first as SendPort;
      return Map<String, dynamic>.from(
        await _request('open', {
              'runtime': runtimeRef,
              'core': corePath,
              'content': contentPath,
              'system': systemDir,
              'save': saveDir,
            })
            as Map,
      );
    } catch (_) {
      await close();
      rethrow;
    } finally {
      ready.close();
      _opening = false;
    }
  }

  Future<dynamic> _request(String command, [dynamic value]) async {
    final port = _commands;
    if (port == null) throw StateError('Worker is closed');
    final reply = ReceivePort();
    try {
      port.send([command, value, reply.sendPort]);
      final result =
          await reply.first.timeout(const Duration(seconds: 30)) as Map;
      if (result.containsKey('error')) {
        throw StateError(result['error'] as String);
      }
      return result['value'];
    } finally {
      reply.close();
    }
  }

  Future<Map<String, dynamic>?> frame({int count = 1}) async {
    if (count < 1 || count > 8) throw RangeError.range(count, 1, 8);
    final value = await _request('frame', count);
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  Future<void> pause(bool value) async {
    await _request('pause', value);
  }

  Future<void> button(int id, bool pressed) async {
    if (id < 0 || id > 15) throw RangeError.range(id, 0, 15);
    await _request('button', [id, pressed]);
  }

  Future<Uint8List> save() async => await _request('save') as Uint8List;
  Future<void> restore(Uint8List bytes) async {
    await _request('restore', bytes);
  }

  /// Applies cheats to the live session. Each entry is
  /// `[index:int, enabled:bool, code:String]`; returns indices the runtime
  /// could not dispatch to a core hook.
  Future<List<int>> applyCheats(List<List<Object>> cheats) async {
    final value = await _request('cheats', cheats);
    return List<int>.from(value as List);
  }

  Future<void> reset() async {
    await _request('reset');
  }

  Future<void> close() async {
    try {
      if (_commands != null) await _request('close');
    } finally {
      _commands = null;
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
    }
  }
}

Future<void> _workerMain(SendPort ready) async {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  EmulationService? service;
  bool paused = false;
  await for (final raw in commands) {
    final message = raw as List;
    final command = message[0] as String;
    final value = message[1];
    final reply = message[2] as SendPort;
    try {
      dynamic result;
      if (command == 'open') {
        final args = value as Map;
        final rt = EzCoreRuntime.fromMarker(
            Map<String, String?>.from(args['runtime'] as Map));
        rt.setDirs(args['system'] as String, args['save'] as String);
        service = EmulationService(runtime: rt);
        await service.start(
          corePath: args['core'] as String,
          romPath: args['content'] as String,
          rom: File(args['content'] as String).readAsBytesSync(),
        );
        final geo = service.geometry;
        result = {
          'name': service.coreName,
          'width': geo.w,
          'height': geo.h,
          'fps': geo.fps,
          'sampleRate': service.sampleRate,
        };
      } else {
        final active = service;
        if (active == null) throw StateError('No session');
        switch (command) {
          case 'frame':
            if (!paused) {
              final pcm = BytesBuilder(copy: false);
              for (var i = 0; i < (value as int); i++) {
                active.runFrame();
                // Fast-forward intentionally mutes audio but drains each frame.
                final chunk = BytesBuilder(copy: false);
                active.drainAudio(active.audioPending, chunk);
                if (value == 1) pcm.add(chunk.takeBytes());
              }
              final rgba = active.frameBytes();
              if (rgba != null) {
                result = {
                  'width': active.frameWidth,
                  'height': active.frameHeight,
                  'rgba': rgba,
                  'pcm': pcm.takeBytes(),
                };
              }
            }
          case 'pause':
            paused = value as bool;
            if (paused) {
              for (var id = 0; id < 16; id++) {
                active.setButton(0, id, false);
              }
            }
          case 'button':
            active.setButton(0, value[0] as int, value[1] as bool);
          case 'save':
            result = active.saveState();
            if (result == null) {
              throw StateError('Core does not support save states');
            }
          case 'cheats':
            final list = (value as List).cast<List>();
            result = active.applyCheats([
              for (final e in list)
                (
                  index: e[0] as int,
                  enabled: e[1] as bool,
                  code: e[2] as String
                ),
            ]);
          case 'restore':
            if (!active.loadState(value as Uint8List)) {
              throw StateError('Core rejected save state');
            }
          case 'reset':
            active.reset();
          case 'close':
            active.close();
          default:
            throw StateError('Unknown worker command: $command');
        }
      }
      reply.send({'value': result});
    } catch (error) {
      reply.send({'error': error.toString()});
    }
    if (command == 'close') {
      commands.close();
      break;
    }
  }
}
