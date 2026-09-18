import 'package:ezcore/runtime/ezcore_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default runtime loader opens the built ezCore runtime', () {
    final runtime = EzCoreRuntime.load();
    expect(runtime.abiVersion(), 1);
  });
}
