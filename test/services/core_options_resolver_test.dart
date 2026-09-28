import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/core_options_resolver.dart';

void main() {
  group('CoreOptionsResolver', () {
    test('only global set -> global wins', () {
      final r = CoreOptionsResolver()..setGlobal('fps', '60');
      final resolved = r.resolve(['fps']);
      expect(resolved['fps']!.value, '60');
      expect(resolved['fps']!.layer, CoreOptionLayer.global);
      expect(resolved['fps']!.layerName, 'global');
    });

    test('system beats global', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setSystem('fps', '120');
      final resolved = r.resolve(['fps']);
      expect(resolved['fps']!.value, '120');
      expect(resolved['fps']!.layer, CoreOptionLayer.system);
      expect(resolved['fps']!.layerName, 'system');
    });

    test('core beats system beats global', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setSystem('fps', '120')
        ..setCore('fps', '240');
      final resolved = r.resolve(['fps']);
      expect(resolved['fps']!.value, '240');
      expect(resolved['fps']!.layer, CoreOptionLayer.core);
    });

    test('game beats core beats system beats global', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setSystem('fps', '120')
        ..setCore('fps', '240')
        ..setGame('fps', '480');
      final resolved = r.resolve(['fps']);
      expect(resolved['fps']!.value, '480');
      expect(resolved['fps']!.layer, CoreOptionLayer.game);
    });

    test('missing key falls through; absent-from-all key omitted', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setCore('rewind', 'enabled')
        ..setGame('fps', '480');
      final resolved = r.resolve(['fps', 'rewind', 'missing']);
      // fps: game beats global
      expect(resolved['fps']!.value, '480');
      expect(resolved['fps']!.layer, CoreOptionLayer.game);
      // rewind only on core layer -> falls through to core
      expect(resolved['rewind']!.value, 'enabled');
      expect(resolved['rewind']!.layer, CoreOptionLayer.core);
      // key absent from every layer -> omitted
      expect(resolved.containsKey('missing'), isFalse);
    });

    test('identical values at two layers resolve to the deeper layer', () {
      final r = CoreOptionsResolver()
        ..setSystem('fps', '60')
        ..setCore('fps', '60'); // same value
      final resolved = r.resolve(['fps']);
      expect(resolved['fps']!.value, '60');
      expect(resolved['fps']!.layer, CoreOptionLayer.core);
      expect(resolved['fps']!.layerName, 'core');
    });

    test('identical values at game and global: game wins', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setGame('fps', '60');
      final resolved = r.resolve(['fps']);
      expect(resolved['fps']!.value, '60');
      expect(resolved['fps']!.layer, CoreOptionLayer.game);
    });

    test('distinct keys per layer resolve independently', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setCore('aspect', 'correct')
        ..setGame('rewind', 'on');
      final resolved = r.resolve(['fps', 'aspect', 'rewind']);
      expect(resolved['fps']!.layer, CoreOptionLayer.global);
      expect(resolved['aspect']!.value, 'correct');
      expect(resolved['aspect']!.layer, CoreOptionLayer.core);
      expect(resolved['rewind']!.value, 'on');
      expect(resolved['rewind']!.layer, CoreOptionLayer.game);
    });

    test('result reflects state at call time (later sets dont affect it)', () {
      final r = CoreOptionsResolver()..setGlobal('fps', '60');
      final first = r.resolve(['fps']);
      r.setGlobal('fps', '1000');
      final second = r.resolve(['fps']);
      expect(first['fps']!.value, '60');
      expect(second['fps']!.value, '1000');
    });

    test('resolveAll merges keys from every layer', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setCore('rewind', 'off')
        ..setGame('fps', '480');
      final all = r.resolveAll();
      expect(all.keys.toSet(), {'fps', 'rewind'});
      expect(all['fps']!.layer, CoreOptionLayer.game);
      expect(all['rewind']!.layer, CoreOptionLayer.core);
    });

    test('clearLayer drops a layer and falls through', () {
      final r = CoreOptionsResolver()
        ..setGlobal('fps', '60')
        ..setGame('fps', '480');
      expect(r.resolve(['fps'])['fps']!.layer, CoreOptionLayer.game);
      r.clearLayer(CoreOptionLayer.game);
      final resolved = r.resolve(['fps']);
      expect(resolved['fps']!.layer, CoreOptionLayer.global);
      expect(resolved['fps']!.value, '60');
    });

    test('resolve with no layers set returns empty', () {
      final r = CoreOptionsResolver();
      expect(r.resolve(['fps']), isEmpty);
      expect(r.resolveAll(), isEmpty);
    });

    test('resolve with no requested keys returns empty', () {
      final r = CoreOptionsResolver()..setGlobal('fps', '60');
      expect(r.resolve([]), isEmpty);
    });
  });
}
