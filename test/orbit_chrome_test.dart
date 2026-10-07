// The OS bar's status corner shows only what is true: the time, and P1 only
// while a controller is connected.
import 'package:ezcore/theme/tokens.dart';
import 'package:ezcore/widgets/orbit_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clock, and P1 only while a controller is connected', (t) async {
    void Function(bool, String)? connection;
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: Scaffold(
          body: OrbitStatus(
            now: () => DateTime(2026, 10, 2, 9, 5),
            subscribeConnection: (cb) {
              connection = cb;
              return () => connection = null;
            },
          ),
        ),
      ),
    );
    expect(find.text('09:05'), findsOneWidget);
    expect(find.text('P1'), findsNothing);
    connection!(true, 'Xbox Wireless Controller');
    await t.pump();
    expect(find.text('P1'), findsOneWidget);
    expect(
      find.byTooltip('Xbox Wireless Controller connected'),
      findsOneWidget,
    );
    connection!(false, 'Xbox Wireless Controller');
    await t.pump();
    expect(find.text('P1'), findsNothing);
  });

  testWidgets('key hints list each key and what it does', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: Tokens.theme(),
        home: const Scaffold(
          body: OrbitKeyHints(
            hints: [
              (['←', '→'], 'Browse'),
              (['1–4'], 'Switch space'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('1–4'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
