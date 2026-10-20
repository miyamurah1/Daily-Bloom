// Interaction tests for the daily-use flows: search, store (offline honesty),
// quick-add from the FAB, and tab navigation.
import 'dart:convert';

import 'package:daily_bloom/data/mock_data.dart';
import 'package:daily_bloom/data/simple_mode.dart';
import 'package:daily_bloom/data/task_repository.dart';
import 'package:daily_bloom/screens/app_shell.dart';
import 'package:daily_bloom/screens/home_screen.dart';
import 'package:daily_bloom/screens/search_screen.dart';
import 'package:daily_bloom/screens/store_screen.dart';
import 'package:daily_bloom/screens/focus_timer_screen.dart';
import 'package:daily_bloom/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TaskRepository.instance.debugReset();
  });

  testWidgets('search finds cached tasks offline', (tester) async {
    // Seed the repository cache so the search has something to find.
    SharedPreferences.setMockInitialValues({
      'bloom_tasks_cache_v2': jsonEncode([
        {'id': 't1', 'title': 'Write the spec', 'tag': 'Work', 'status': 'todo'},
        {'id': 't2', 'title': 'Buy milk', 'tag': 'Home', 'status': 'todo'},
      ]),
    });
    await TaskRepository.instance.init();
    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Search tasks'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'spec');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Write the spec'), findsOneWidget);
    expect(find.text('Buy milk'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search shows an honest empty state for no matches',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'bloom_tasks_cache_v2': jsonEncode([
        {'id': 't1', 'title': 'Write the spec', 'tag': 'Work', 'status': 'todo'},
      ]),
    });
    await TaskRepository.instance.init();
    await tester.pumpWidget(const MaterialApp(home: SearchScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.enterText(find.byType(TextField).first, 'zzzzzz');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('No blooms found.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('store renders the catalog offline with an honest note',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pump(tester, const StoreScreen());
    expect(find.text('Kyoto Garden'), findsOneWidget);
    expect(find.text('Edo Period'), findsOneWidget);
    expect(find.text('Offline — connect to buy or equip themes.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('store action pills render for owned and unowned themes',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await _pump(tester, const StoreScreen());
    expect(find.text('EQUIP'), findsWidgets);
    expect(find.text('◆ 500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('long-press on a task card fires the context-menu hook',
      (tester) async {
    var pressed = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: TaskCard(
            task: const Task(id: 't1', title: 'Deep work', tag: 'Work'),
            onLongPress: () => pressed++,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.longPress(find.text('Deep work'));
    await tester.pump();
    expect(pressed, 1);
  });

  testWidgets('focus timer renders the preset picker', (tester) async {
    await _pump(tester, const FocusTimerScreen());
    expect(find.text('25:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('app shell', () {
    testWidgets('simple mode is the default (calm, focused home)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('Today\'s focus'), findsOneWidget);
    });

    testWidgets('toggling simple mode off keeps the home usable',
        (tester) async {
      await SimpleMode.instance.setEnabled(false);
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
      expect(find.text('Today\'s focus'), findsOneWidget);
    });

    testWidgets('home shows the honest offline note when the API is down',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('showing your saved tasks'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('quick-add from the FAB plants into the repository',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: AppShell()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Quick plant'), findsOneWidget);

      await tester.enterText(
          find.byType(TextField).first, 'Ship the release');
      await tester.tap(find.text('Plant bloom'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(TaskRepository.instance.tasks.map((t) => t.title),
          contains('Ship the release'));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
