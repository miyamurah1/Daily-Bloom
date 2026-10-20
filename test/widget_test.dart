// Daily Bloom widget tests — auth-gated entry point.
//
// The app boots to AuthGate: splash -> LoginScreen (logged out) or
// AppShell (logged in). SharedPreferences is mocked so restore()
// completes without platform channels. Firebase has no native app in
// tests, so AuthGate degrades to the logged-out stream (see _authState).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_bloom/main.dart';

void main() {

  testWidgets('Boot shows welcome gate when no session is stored', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const DailyBloomApp());
    // Splash first (restore is async), then welcome gate. Avoid
    // pumpAndSettle: the splash spinner never "settles".
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Daily Bloom'), findsOneWidget);
    expect(find.text('Continue as Guest'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('Welcome gate offers guest and sign-in', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const DailyBloomApp());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('One task. One timer. One focus.'), findsOneWidget);
    expect(find.textContaining('Add up to 3 tasks'), findsOneWidget);
  });
}
