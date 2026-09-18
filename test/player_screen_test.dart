import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ezcore/screens/player_screen.dart';
import 'package:ezcore/models/game_entry.dart';
import 'package:ezcore/state/app_state.dart';

void main() {
  // This file currently verifies failure chrome only. A successful native
  // widget launch was not established by the previous fake-async harness.
  // Controller tests prove frame decoding, not end-to-end player UI behavior.
  testWidgets('missing core shows launch failure, not simulated gameplay', (
    tester,
  ) async {
    final state = AppState.ephemeral();
    state.addGame(
      const GameEntry(
        id: 'missing',
        title: 'Missing content',
        system: 'gba',
        extension: 'gba',
        filePath: '/missing.gba',
        coreId: 'missing',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerScreen(gameId: 'missing', state: state),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Launch failed'), findsOneWidget);
    expect(find.textContaining('Native canvas binds'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
