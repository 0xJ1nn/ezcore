import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/services/cover_art.dart';

void main() {
  test('cover spec is deterministic per game id', () {
    final a = coverSpecFor('imp-test-rom');
    final b = coverSpecFor('imp-test-rom');
    expect(a.top, b.top);
    expect(a.bottom, b.bottom);
    expect(a.motif, b.motif);
    expect(a.accent, b.accent);
  });

  test('cover spec stays inside the approved identity ranges', () {
    for (final id in ['a', 'zelda', 'mario-kart-64', 'imp-xyz', 'homebrew']) {
      final spec = coverSpecFor(id);
      expect(spec.motif, inInclusiveRange(0, 4));
      expect(
        [spec.top, spec.bottom].every((c) => c >= 0xFF0A0A0A && c <= 0xFF2A3542),
        isTrue,
        reason: 'palette must stay dark navy/slate for $id',
      );
    }
  });

  test('different games spread across palettes and motifs', () {
    final ids = List.generate(24, (i) => 'game-$i');
    final tops = ids.map((id) => coverSpecFor(id).top).toSet();
    final motifs = ids.map((id) => coverSpecFor(id).motif).toSet();
    expect(tops.length, greaterThan(1));
    expect(motifs.length, greaterThan(1));
  });

  test('no pinned screenshot cover resolves to null', () {
    expect(coverFileFor('definitely-not-a-real-game-id-12345'), isNull);
  });
}
