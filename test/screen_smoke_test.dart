// Render smoke tests for the screens that previously had ~0% coverage.
// Each screen is pumped offline and asserted to lay out without throwing
// and to show a stable marker. Cheap, broad regression safety.
import 'package:daily_bloom/screens/activity_screen.dart';
import 'package:daily_bloom/screens/flow_canvas_screen.dart';
import 'package:daily_bloom/screens/inbox_screen.dart';
import 'package:daily_bloom/screens/onboarding_screen.dart';
import 'package:daily_bloom/screens/rules_screen.dart';
import 'package:daily_bloom/screens/search_screen.dart';
import 'package:daily_bloom/screens/settings_screen.dart';
import 'package:daily_bloom/screens/signup_screen.dart';
import 'package:daily_bloom/screens/store_screen.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    theme: SakuraTheme.buildTheme(),
    home: screen,
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SakuraTheme.useGoogleFonts = false;
  });

  final screens = <String, Widget>{
    'SettingsScreen': const SettingsScreen(),
    'SearchScreen': const SearchScreen(),
    'InboxScreen': const InboxScreen(),
    'StoreScreen': const StoreScreen(),
    'SignupScreen': const SignupScreen(),
    'ActivityScreen': const ActivityScreen(),
    'RulesScreen': const RulesScreen(),
    'FlowCanvasScreen': const FlowCanvasScreen(),
  };

  screens.forEach((name, widget) {
    testWidgets('$name renders offline without error', (tester) async {
      await _pump(tester, widget);
      expect(tester.takeException(), isNull, reason: name);
    });
  });

  testWidgets('OnboardingScreen shows welcome + CTA, completes once',
      (tester) async {
    var done = 0;
    await _pump(tester, OnboardingScreen(onDone: () => done++));
    expect(tester.takeException(), isNull);
    expect(find.text('Welcome to Daily Bloom'), findsOneWidget);

    // Advance to the final slide and finish. No perpetual animation on
    // this screen, so pumpAndSettle is safe.
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    // Step 4 — make it yours: name, focus chips, two switches.
    expect(find.text('Make it yours'), findsOneWidget);
    expect(find.text('Enter my garden'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Maya');
    // Choose "No rituals" so finish() skips the preset (prefs-only path
    // — the widget test's fake-async zone can't complete real I/O).
    await tester.ensureVisible(find.text('No rituals'));
    await tester.tap(find.text('No rituals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enter my garden'));
    await tester.pumpAndSettle();
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });
}
