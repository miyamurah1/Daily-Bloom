// Text-scaling audit: the app supports system scale up to 200% (see
// main.dart), so 2.0 is the worst case the layout must survive. Every
// primary surface must lay out with zero overflow at that scale.
import 'package:daily_bloom/data/mock_data.dart';
import 'package:daily_bloom/screens/app_shell.dart';
import 'package:daily_bloom/screens/goals_screen.dart';
import 'package:daily_bloom/screens/habits_screen.dart';
import 'package:daily_bloom/screens/home_screen.dart';
import 'package:daily_bloom/screens/insights_screen.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';
import 'package:daily_bloom/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scale = TextScaler.linear(2.0);

Future<void> _pump(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(textScaler: _scale),
      child: child,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SakuraTheme.useGoogleFonts = false;
  });

  testWidgets('Home survives 2.0x text scale', (tester) async {
    await _pump(tester, 360, const HomeScreen());
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppShell survives 2.0x text scale', (tester) async {
    await _pump(tester, 390, const AppShell());
    expect(tester.takeException(), isNull);
  });

  testWidgets('insights screen survives 2.0x text scale', (tester) async {
    await _pump(tester, 390, const InsightsScreen(embedded: true));
    expect(tester.takeException(), isNull);
  });

  for (final entry in <String, Widget>{
    'Habits': const HabitsScreen(),
    'Goals': const GoalsScreen(),
  }.entries) {
    testWidgets('${entry.key} survives 2.0x text scale', (tester) async {
      await _pump(tester, 390, entry.value);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('TaskCard survives 2.0x text scale', (tester) async {
    const task = Task(
      id: 'ts1',
      title: 'A deliberately long task title that would wrap several lines',
      tag: 'General',
      description: 'Long description copy to stress the secondary line.',
    );
    await _pump(
      tester,
      360,
      const Scaffold(
        body: SingleChildScrollView(child: TaskCard(task: task)),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
