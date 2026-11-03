// Regression coverage for the 10/10 UI/UX pass:
// - nav consolidated to 4 ergonomic tabs
// - card body opens detail; the ring owns completion; subtasks toggle
//   freely (no confirm dialog, no one-way lock-in)
import 'dart:convert';

import 'package:daily_bloom/data/api_client.dart';
import 'package:daily_bloom/data/mock_data.dart';
import 'package:daily_bloom/data/task_repository.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';
import 'package:daily_bloom/widgets/contribution_heatmap.dart';
import 'package:daily_bloom/widgets/petal_burst.dart';
import 'package:daily_bloom/widgets/sakura_bottom_nav.dart';
import 'package:daily_bloom/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Inter is an HTTP fetch: keep theme builds synchronous + offline
    // inside widget tests. Production still uses GoogleFonts.
    SakuraTheme.useGoogleFonts = false;
  });

  test('bottom nav consolidates to four ergonomic tabs', () {
    expect(SakuraBottomNav.items.length, 4);
    expect(SakuraBottomNav.labels, ['Today', 'Rituals', 'Folders', 'Insights']);
  });

  testWidgets('card body opens, ring completes, subtasks toggle freely',
      (tester) async {
    var opened = 0;
    var toggled = 0;
    String? subId;
    bool? subDone;

    final sub = Subtask(
      id: 's1',
      taskId: 't1',
      title: 'Draft outline',
      startedAt: DateTime(2026, 1, 1),
    );
    final task = Task(
      id: 't1',
      title: 'Write the launch note',
      tag: 'Work',
      subtasks: [sub],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskCard(
          task: task,
          onOpen: () => opened++,
          onToggle: () => toggled++,
          onToggleSub: (s, done) {
            subId = s.id;
            subDone = done;
          },
        ),
      ),
    ));
    await tester.pump();

    // Title (card body) opens the detail — it must NOT complete the task.
    await tester.tap(find.text('Write the launch note'));
    await tester.pump();
    expect(opened, 1);
    expect(toggled, 0, reason: 'body tap opens, does not toggle');

    // The dedicated ring is the completion target.
    await tester.tap(find.bySemanticsLabel('Mark task done'));
    await tester.pump();
    expect(toggled, 1);
    expect(opened, 1, reason: 'ring tap does not open');

    // A subtask toggles in one tap, with no blocking confirm dialog.
    await tester.tap(find.text('Draft outline'));
    await tester.pump();
    expect(subId, 's1');
    expect(subDone, isTrue);
    expect(find.byType(AlertDialog), findsNothing);

    // Let the UNDO snackbar's timer drain so the test ends clean.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('a completed subtask can be reopened (no lock-in)',
      (tester) async {
    bool? next;
    final sub = Subtask(
      id: 's2',
      taskId: 't2',
      title: 'Already done',
      done: true,
      startedAt: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 2),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskCard(
          task: Task(id: 't2', title: 'T', tag: 'X', subtasks: [sub]),
          onToggleSub: (s, done) => next = done,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Already done'));
    await tester.pump();
    expect(next, isFalse, reason: 'done subtask toggles back to open');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  test('repository restores cached tasks when offline', () async {
    SharedPreferences.setMockInitialValues({
      'bloom_tasks_cache_v2': jsonEncode([
        {
          'id': 'c1',
          'title': 'Cached bloom',
          'tag': 'Work',
          'folder': 'Work',
          'status': 'todo',
        }
      ]),
    });
    await TaskRepository.instance.init();
    expect(TaskRepository.instance.tasks.map((t) => t.title),
        contains('Cached bloom'));
  });

  testWidgets('heatmap cells pop an inline tooltip, never a snackbar',
      (tester) async {
    final days = List.generate(
      28,
      (i) => HeatDay(
        date: DateTime(2026, 1, 1).add(Duration(days: i)),
        count: i % 6,
        level: i % 6,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ContributionHeatmap(days: days),
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(Tooltip).last);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);

    // Drain the tooltip's own show timer.
    await tester.pump(const Duration(seconds: 4));
  });

  test('dark palette builds a dark, contrast-correct ThemeData', () {
    ThemeStore.instance.themeId = 'midnight';
    SakuraColors.setActive(AppThemes.midnight);
    final dark = SakuraTheme.buildTheme();
    expect(dark.brightness, Brightness.dark);
    expect(dark.colorScheme.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, AppThemes.midnight.background);

    ThemeStore.instance.themeId = 'kyoto';
    SakuraColors.setActive(AppThemes.kyoto);
    final light = SakuraTheme.buildTheme();
    expect(light.brightness, Brightness.light);
    expect(light.colorScheme.brightness, Brightness.light);
  });

  testWidgets('palette resolves from ThemeData, not the global',
      (tester) async {
    // Inject Edo through one subtree while the global still says
    // midnight: `context.bloom` must follow the tree, proving tests can
    // theme without touching globals. Both branches live in ONE frame so
    // no cross-pump element reuse can leak the inherited theme.
    SakuraColors.setActive(AppThemes.midnight);
    AppThemeData? fromTree;
    AppThemeData? fromFallback;
    await tester.pumpWidget(MaterialApp(
      home: Column(
        children: [
          Theme(
            data: ThemeData(
              extensions: const [SakuraThemeExtension(AppThemes.sakura)],
            ),
            child: Builder(
              builder: (context) {
                fromTree = context.bloom;
                return const SizedBox.shrink();
              },
            ),
          ),
          Builder(
            builder: (context) {
              fromFallback = context.bloom;
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    ));
    expect(fromTree?.id, 'edo');
    expect(fromFallback?.id, 'midnight');
  });

  test('theme extension lerps without popping', () {
    const a = SakuraThemeExtension(AppThemes.sakura);
    const b = SakuraThemeExtension(AppThemes.midnight);
    expect(a.lerp(b, 0).data.id, 'edo');
    expect(a.lerp(b, 1).data.id, 'midnight');
    final mid = a.lerp(b, 0.5).data;
    expect(mid.primary, Color.lerp(AppThemes.sakura.primary,
        AppThemes.midnight.primary, 0.5));
    expect(a.copyWith().data.id, 'edo');
    expect(a.copyWith(data: AppThemes.midnight).data.id, 'midnight');
  });

  test('offline create + move queue in the persistent FIFO outbox',
      () async {
    SharedPreferences.setMockInitialValues({});
    final repo = TaskRepository.instance;
    final created = await repo.createTask(title: 'Offline bloom', tag: 'Idea');
    await repo.moveTask(created.id, 'done');

    // Both mutations are retained in memory…
    expect(repo.pendingMutations, greaterThanOrEqualTo(2));
    // …and persisted to SharedPreferences for the next launch.
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('bloom_outbox_v1');
    expect(raw, isNotNull);
    final kinds =
        (jsonDecode(raw!) as List).map((e) => e['kind']).toList();
    expect(kinds, containsAllInOrder(['create', 'move']));
  });

  testWidgets('completion burst fires once without layout impact',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: PetalBurst(
            onTap: () => taps++,
            child: const SizedBox(width: 24, height: 24),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.byType(PetalBurst));
    await tester.pump();
    // Mid-flight the painter is mounted…
    await tester.pump(const Duration(milliseconds: 150));
    expect(taps, 1);
    // …and it settles cleanly (no lingering controller).
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });
}
