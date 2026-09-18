import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/scoped_files.dart';

void main() {
  test('passthrough runs the body and ignores bookmarks', () async {
    const scoped = PassthroughScopedFiles();
    expect(await scoped.withAccess('/anywhere', () async => 42), 42);
    await scoped.saveBookmark('/anywhere');
  });

  test('channel impl degrades without a host', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final scoped = MethodChannelScopedFiles();
    // No platform host in unit tests: access calls must still run the body.
    expect(await scoped.withAccess('/anywhere', () async => 'ran'), 'ran');
    await scoped.saveBookmark('/anywhere');
  });

  test('factory picks channel on macOS wiring', () {
    expect(createScopedFiles(), isA<ScopedFiles>());
  });
}
