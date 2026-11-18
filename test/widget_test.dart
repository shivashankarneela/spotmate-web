import 'package:flutter_test/flutter_test.dart';
import 'package:spotmate/main.dart' as app;

void main() {
  testWidgets('Shows startup errors when Supabase initialization fails',
      (tester) async {
    const message = 'Missing SUPABASE_PUBLISHABLE_KEY';
    final previousError = app.initError;
    addTearDown(() => app.initError = previousError);
    app.initError = message;

    await tester.pumpWidget(const app.SpotmateApp());

    expect(find.text('Init Error: $message'), findsOneWidget);
    expect(find.byType(app.AuthGate), findsNothing);
  });
}
