import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotmate/features/arena_games/space_shooter/space_shooter_screen.dart';

void main() {
  testWidgets('launch poster closes after five seconds without opening the game', (tester) async {
    var launches = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showSpaceShooterLaunch(context, onPlay: (_) async { launches++; }),
        child: const Text('Show poster'),
      ))),
    ));
    await tester.tap(find.text('Show poster'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('12 missions · Free to play'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Play now'), findsNothing);
    expect(launches, 0);
  });

  testWidgets('Play now opens the game exactly once and cancels the poster timer', (tester) async {
    var launches = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => TextButton(
        onPressed: () => showSpaceShooterLaunch(context, onPlay: (_) async { launches++; }),
        child: const Text('Show poster'),
      ))),
    ));
    await tester.tap(find.text('Show poster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play now'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Play now'), findsNothing);
    expect(launches, 1);
  });
}
