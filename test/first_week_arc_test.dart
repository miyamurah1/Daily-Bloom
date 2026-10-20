// First-week arc: the nameplate is a one-time hero intro — it shows on the
// first launch, then collapses to the thin prompt row forever after.
import 'package:daily_bloom/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        'bloom_concept_seen_v1': true,
      }));

  testWidgets('nameplate shows on first launch', (tester) async {
    await _pumpHome(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('YOUR FIRST WEEK'), findsOneWidget);
  });

  testWidgets('nameplate collapses after the arc is opened once',
      (tester) async {
    await _pumpHome(tester);
    expect(find.text('YOUR FIRST WEEK'), findsOneWidget);

    // Open the arc (step 0 opens the quick-add sheet), then dismiss it.
    await tester.tap(find.byKey(const ValueKey('home_arc_card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('YOUR FIRST WEEK'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // Persisted: a fresh Home never shows the nameplate again.
    await _pumpHome(tester);
    expect(find.text('YOUR FIRST WEEK'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
