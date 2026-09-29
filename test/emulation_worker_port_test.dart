import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/emu/emulation_worker.dart';

/// One recorded `setButton(port, id, pressed)` call.
typedef _Call = (int port, int id, bool pressed);

void Function(int, int, bool) _record(List<_Call> sink) =>
    (int port, int id, bool pressed) => sink.add((port, id, pressed));

void main() {
  // The native runtime keeps four controller ports live
  // (`uint32_t input_buttons[4]` in the C bridge), so the Dart worker has to
  // carry the port through to `setButton`. These tests pin that routing: they
  // fail against the old worker, which hardcoded port 0 for every button.
  group('button command port routing', () {
    test('a button addressed to port 2 reaches setButton(2, ...)', () {
      final calls = <_Call>[];
      // Old behaviour hardcoded port 0 here, so player two's pad drove
      // player one; this expectation is what the fix makes true.
      dispatchButton(_record(calls), [2, 1, true]);
      expect(calls, [(2, 1, true)]);
    });

    test('port 0 still works unchanged', () {
      final calls = <_Call>[];
      dispatchButton(_record(calls), [0, 1, true]);
      expect(calls, [(0, 1, true)]);
    });

    test('each of the four ports is forwarded verbatim', () {
      for (var port = 0; port < kControllerPorts; port++) {
        final calls = <_Call>[];
        dispatchButton(_record(calls), [port, 3, false]);
        expect(calls, [(port, 3, false)]);
      }
    });

    test('an out-of-range port throws RangeError', () {
      final calls = <_Call>[];
      for (final bad in [4, 9, -1]) {
        expect(
          () => dispatchButton(_record(calls), [bad, 0, true]),
          throwsRangeError,
        );
      }
      // Nothing reached the runtime: the reject happens before the dispatch.
      expect(calls, isEmpty);
    });

    test('an out-of-range button id still throws RangeError', () {
      final calls = <_Call>[];
      expect(
        () => dispatchButton(_record(calls), [1, 16, true]),
        throwsRangeError,
      );
      expect(calls, isEmpty);
    });

    test('a malformed payload is rejected with a clear error', () {
      final calls = <_Call>[];
      expect(
        () => dispatchButton(_record(calls), [1, 1]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('[port, id, pressed]'),
          ),
        ),
      );
      expect(calls, isEmpty);
    });
  });

  group('pause releases every port', () {
    test('clearAllButtons releases all 16 buttons on all 4 ports', () {
      final calls = <_Call>[];
      clearAllButtons(_record(calls));
      expect(calls, hasLength(kControllerPorts * 16));
      for (var port = 0; port < kControllerPorts; port++) {
        for (var id = 0; id < 16; id++) {
          expect(calls, contains((port, id, false)));
        }
      }
    });
  });

  group('EmulationWorker.button port argument', () {
    test('rejects a port outside 0..3 before opening a session', () {
      final worker = EmulationWorker();
      expect(() => worker.button(0, true, port: 4), throwsRangeError);
      expect(() => worker.button(0, true, port: -1), throwsRangeError);
    });

    test('still rejects a button id outside 0..15', () {
      final worker = EmulationWorker();
      expect(() => worker.button(16, true), throwsRangeError);
    });
  });
}
