import 'package:daily_bloom/data/api_client.dart';
import 'package:daily_bloom/data/mock_data.dart';
import 'package:daily_bloom/screens/activity_screen.dart';
import 'package:daily_bloom/screens/folder_detail_screen.dart';
import 'package:daily_bloom/screens/flow_canvas_screen.dart';
import 'package:daily_bloom/screens/focus_timer_screen.dart';
import 'package:daily_bloom/screens/inbox_screen.dart';
import 'package:daily_bloom/screens/insights_screen.dart';
import 'package:daily_bloom/screens/onboarding_screen.dart';
import 'package:daily_bloom/screens/review_screen.dart';
import 'package:daily_bloom/screens/rules_screen.dart';
import 'package:daily_bloom/screens/search_screen.dart';
import 'package:daily_bloom/screens/settings_screen.dart';
import 'package:daily_bloom/screens/signup_screen.dart';
import 'package:daily_bloom/screens/store_screen.dart';
import 'package:daily_bloom/screens/task_detail_screen.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SakuraTheme.useGoogleFonts = false;
  });

  final screens = <String, Widget>{
    'Settings': const SettingsScreen(),
    'Search': const SearchScreen(),
    'Inbox': const InboxScreen(),
    'Store': const StoreScreen(),
    'Signup': const SignupScreen(),
    'Activity': const ActivityScreen(),
    'Rules': const RulesScreen(),
    'FlowCanvas': const FlowCanvasScreen(),
    'Insights': const InsightsScreen(embedded: true),
    'Review': const ReviewScreen(embedded: true),
    'TaskDetail': const TaskDetailScreen(
        task: Task(id: 't1', title: 'Write the spec', tag: 'Work')),
    'FocusTimer': const FocusTimerScreen(),
    'FolderDetail': const FolderDetailScreen(
        folder: BloomFolder(name: 'Productivity')),
    'Onboarding': OnboardingScreen(onDone: () {}),
  };

  screens.forEach((name, screen) {
    testWidgets('$name at 200% text scale', (tester) async {
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final errors = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.toString());
      await tester.pumpWidget(MaterialApp(
        theme: SakuraTheme.buildTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: screen,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      FlutterError.onError = prev;
      for (final e in errors) {
        // ignore: avoid_print
        print('>>>[$name] ${e.split('\n').take(6).join('\n')}');
      }
      expect(errors, isEmpty, reason: name);
    });
  });
}
