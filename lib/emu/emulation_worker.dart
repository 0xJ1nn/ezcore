import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../runtime/ezcore_runtime.dart';
import 'core_session_backend.dart';
import 'emulation_service.dart';

/// Controller ports the native runtime keeps live (`input_buttons[4]` in the
/// C bridge). Ports outside this range are rejected before they reach it.
const int kControllerPorts = 4;

/// Decodes a `button` command payload `[port, id, pressed]` and hands it to
/// [send]. Lives outside the isolate loop so port routing is testable without
/// a native session; the worker wires [send] to `EmulationService.setButton`.
void dispatchButton(
  void Function(int port, int id, bool pressed) send,
  dynamic value,
) {
  final list = value as List;
  if (list.length != 3) {
    throw StateError(
      'Malformed button payload: expected [port, id, pressed], '
      'got ${list.length} value(s)',
    );
  }
  final port = list[0] as int;
  final id = list[1] as int;
  final pressed = list[2] as bool;
  if (port < 0 || port >= kControllerPorts) {
    throw RangeError.range(port, 0, kControllerPorts - 1, 'port');
  }
  if (id < 0 || id > 15) throw RangeError.range(id, 0, 15);
  send(port, id, pressed);
}

/// Releases every RetroPad button on every controller port. Used when the
/// session pauses so a button held on any pad is not stuck down afterwards.
void clearAllButtons(void Function(int port, int id, bool pressed) send) {
  for (var port = 0; port < kControllerPorts; port++) {
    for (var id = 0; id < 16; id++) {
      send(port, id, false);
    }
  }
}

/// Single native-session owner. Every native call runs in this isolate.
/// Request/response frames provide backpressure: the host requests the next
/// frame only after consuming the previous video/audio packet. This is NOT
/// process isolation: a native core crash can still terminate the application.
class EmulationWorker implements CoreSessionBackend {
  Isolate? _isolate;
  SendPort? _commands;
  bool _opening = false;

  @override
  Future<Map<String, dynamic>> open({
    required Map<String, String?> runtimeRef,
    required String corePath,
    required String contentPath,
    required String systemDir,
    required String saveDir,
    Map<String, String> coreOptions = const {},
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
              'options': coreOptions,
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

  @override
  Future<Map<String, dynamic>?> frame({int count = 1}) async {
    if (count < 1 || count > 8) throw RangeError.range(count, 1, 8);
    final value = await _request('frame', count);
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  @override
  Future<void> pause(bool value) async {
    await _request('pause', value);
  }

  /// Sends a RetroPad button transition for controller [port] (0-3, port 0
  /// is player one). Defaults to 0 so single-player callers are unchanged.
  @override
  Future<void> button(int id, bool pressed, {int port = 0}) async {
    if (id < 0 || id > 15) throw RangeError.range(id, 0, 15);
    if (port < 0 || port >= kControllerPorts) {
      throw RangeError.range(port, 0, kControllerPorts - 1, 'port');
    }
    await _request('button', [port, id, pressed]);
  }

  @override
  Future<Uint8List> save() async => await _request('save') as Uint8List;
  @override
  Future<void> restore(Uint8List bytes) async {
    await _request('restore', bytes);
  }

  /// Applies cheats to the live session. Each entry is
  /// `[index:int, enabled:bool, code:String]`; returns indices the runtime
  /// could not dispatch to a core hook.
  @override
  Future<List<int>> applyCheats(List<List<Object>> cheats) async {
    final value = await _request('cheats', cheats);
    return List<int>.from(value as List);
  }

  @override
  Future<void> reset() async {
    await _request('reset');
  }

  /// Reads back the option set the loaded core registered. Each entry is
  /// `{key, default, value}`; empty when the core registers no options.
  @override
  Future<List<Map<String, String>>> coreOptions() async {
    final value = await _request('options');
    return [
      for (final e in (value as List).cast<Map>()) Map<String, String>.from(e),
    ];
  }

  /// Sets one core option on the live session. Returns false when the key
  /// matched no registered option — surfacing user-data mistakes honestly
  /// instead of throwing.
  @override
  Future<bool> setCoreOption(String key, String value) async =>
      await _request('setOption', {'key': key, 'value': value}) as bool;

  @override
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
          Map<String, String?>.from(args['runtime'] as Map),
        );
        rt.setDirs(args['system'] as String, args['save'] as String);
        service = EmulationService(runtime: rt);
        await service.start(
          corePath: args['core'] as String,
          romPath: args['content'] as String,
          rom: File(args['content'] as String).readAsBytesSync(),
          coreOptions: Map<String, String>.from(
            (args['options'] as Map?) ?? const {},
          ),
        );
        final geo = service.geometry;
        result = {
          'name': service.coreName,
          'width': geo.w,
          'height': geo.h,
          'fps': geo.fps,
          'sampleRate': service.sampleRate,
          'rejectedOptions': service.rejectedCoreOptions,
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
              // Release every button on every port: a pad held by player two
              // would otherwise stay stuck down across the pause.
              clearAllButtons(active.setButton);
            }
          case 'button':
            dispatchButton(active.setButton, value);
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
                  code: e[2] as String,
                ),
            ]);
          case 'restore':
            if (!active.loadState(value as Uint8List)) {
              throw StateError('Core rejected save state');
            }
          case 'reset':
            active.reset();
          case 'options':
            // Read-back of the option set the core registered: a list of
            // records (key, defaultValue, value) the UI can render as-is.
            result = active
                .coreOptions()
                .map(
                  (o) => {
                    'key': o.key,
                    'default': o.defaultValue,
                    'value': o.value,
                  },
                )
                .toList();
          case 'setOption':
            final args = value as Map;
            // False means the key matched no registered option; surface
            // that to the caller instead of throwing — an unknown option
            // is user data, not a program fault.
            result = active.setCoreOption(
              args['key'] as String,
              args['value'] as String,
            );
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
