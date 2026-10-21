// Regression coverage for the audit fixes:
// - the Rituals hub re-homes the previously orphaned Goals dashboard
// - theme preview restores the real theme even across rapid previews
import 'package:daily_bloom/data/inbox_store.dart';
import 'package:daily_bloom/screens/app_shell.dart';
import 'package:daily_bloom/screens/habits_screen.dart';
import 'package:daily_bloom/screens/insights_hub_screen.dart';
import 'package:daily_bloom/screens/insights_screen.dart';
import 'package:daily_bloom/screens/rituals_hub_screen.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';
import 'package:daily_bloom/widgets/sakura_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SakuraTheme.useGoogleFonts = false;
    InboxStore.instance.setUnread(0);
  });

  testWidgets('Rituals hub switches Habits <-> Goals (Goals reachable)',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: RitualsHubScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);

    // Habits is the default segment.
    expect(find.text('Habits'), findsWidgets);

    // Switch to the Goals dashboard — its header proves it rendered.
    await tester.tap(find.text('Goals'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text('目標'), findsOneWidget);
  });

  test('theme preview returns to the pre-preview theme after rapid previews',
      () async {
    ThemeStore.instance.themeId = 'midnight';
    SakuraColors.setActive(AppThemes.midnight);

    ThemeStore.instance
        .preview('kyoto', duration: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ThemeStore.instance
        .preview('ocean', duration: const Duration(milliseconds: 20));
    expect(ThemeStore.instance.themeId, 'ocean');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    // Not kyoto (the bug) — the true original.
    expect(ThemeStore.instance.themeId, 'midnight');
  });

  testWidgets('Inbox badge clears immediately when unread drops to zero',
      (tester) async {
    Finder badge() => find.byWidgetPredicate((w) =>
        w is Semantics &&
        (w.properties.label ?? '') == 'Inbox, unread notifications');

    await tester.pumpWidget(const MaterialApp(home: InsightsHubScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(badge(), findsNothing);

    // New mail arrives → dot appears.
    InboxStore.instance.setUnread(3);
    await tester.pump();
    expect(badge(), findsOneWidget);

    // Read the messages → dot clears without leaving the tab.
    InboxStore.instance.setUnread(0);
    await tester.pump();
    expect(badge(), findsNothing);
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics && (w.properties.label ?? '') == 'Inbox'),
        findsOneWidget);
  });

  // --- Theme swap ------------------------------------------------------
  // The hubs cache visited sections in an IndexedStack. A const child
  // canonicalises to the identical widget instance on rebuild, Flutter
  // skips the child update and the section keeps painting the previous
  // palette — the "theme won't apply" bug AppShell documents for its
  // own tab pages, reproduced here on the inner hub screens.

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ListenableBuilder(
        listenable: ThemeStore.instance,
        builder: (_, __) => MaterialApp(
          theme: SakuraTheme.buildTheme(),
          home: const AppShell(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> tapNav(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(
      of: find.byType(SakuraBottomNav),
      matching: find.text(label),
    ));
    // Fixed pumps — pumpAndSettle never settles (ambient tickers).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Background of the Scaffold owned by [T] (first Scaffold in its
  /// subtree — nested hubs add their own above the section's one).
  Color bgOf<T extends Widget>(WidgetTester tester) => tester
      .widget<Scaffold>(
        find
            .descendant(
              of: find.byType(T),
              matching: find.byType(Scaffold),
            )
            .first,
      )
      .backgroundColor!;

  testWidgets('theme swap repaints the Insights hub section', (tester) async {
    ThemeStore.instance.resetToDefault();
    await pumpShell(tester);
    await tapNav(tester, 'Insights');
    expect(find.byType(InsightsScreen), findsOneWidget);
    expect(bgOf<InsightsScreen>(tester), AppThemes.sakura.background);

    await ThemeStore.instance.equip(() async {}, 'midnight');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bgOf<InsightsScreen>(tester), AppThemes.byId('midnight').background,
        reason: 'the section must repaint on a theme swap');
    ThemeStore.instance.resetToDefault();
  });

  testWidgets('theme swap repaints the Rituals hub section', (tester) async {
    ThemeStore.instance.resetToDefault();
    await pumpShell(tester);
    await tapNav(tester, 'Habits');
    expect(find.byType(HabitsScreen), findsOneWidget);
    expect(bgOf<HabitsScreen>(tester), AppThemes.sakura.background);

    await ThemeStore.instance.equip(() async {}, 'midnight');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(bgOf<HabitsScreen>(tester), AppThemes.byId('midnight').background,
        reason: 'the section must repaint on a theme swap');
    ThemeStore.instance.resetToDefault();
  });
}
