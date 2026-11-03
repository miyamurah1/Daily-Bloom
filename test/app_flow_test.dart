// App-level flow test: runs on the VM in the normal `flutter test` suite
// (and therefore in CI), mirroring `integration_test/app_test.dart` which
// runs the same flow on a real device/emulator.
//
// Pumps the real AppShell and exercises the flagship loop: quick-add a
// task via the FAB, confirm it lands in the repository, switch tabs.
// Bounded pumps only — the ambient bloom background never settles.
import 'package:daily_bloom/data/task_repository.dart';
import 'package:daily_bloom/screens/app_shell.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bloom_onboarding_seen_v1': true,
      'bloom_concept_seen_v1': true,
    });
    SakuraTheme.useGoogleFonts = false;
  });

  testWidgets('shell boots, plants a task via the FAB, and switches tabs',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppShell()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Plant a task: FAB -> quick-add sheet -> repository.
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Quick plant'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Integration bloom');
    await tester.pump();
    await tester.tap(find.text('Plant bloom'));
    // Sequence: start flourish -> finish it (fires onEnd -> pop) -> let the
    // sheet's pop animation run -> let the "Planted" SnackBar expire so it
    // does not overlap the bottom nav.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 4));

    expect(
      TaskRepository.instance.tasks.any((t) => t.title == 'Integration bloom'),
      isTrue,
      reason: 'the task was planted into the repository',
    );
    expect(tester.takeException(), isNull);

    // Navigate the four tabs, verifying each renders without error.
    for (final label in ['Rituals', 'Folders', 'Insights', 'Today']) {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: 'tab $label');
    }
  });
}
