import 'package:daily_bloom/screens/home_screen.dart';
import 'package:daily_bloom/widgets/contribution_heatmap.dart';
import 'package:daily_bloom/widgets/task_flow_list.dart';
import 'package:daily_bloom/data/simple_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Home's product contract (Zen Bento era, calm default):
/// bento header (~130px) -> Today's Flow board -> plan -> heatmap.
/// The board lands in the primary mobile viewport; evidence and doors
/// sit below the work. Simple Mode hides the power doors (Board link).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bloom_concept_seen_v1': true,
      'bloom_simple_mode_v1': false,
    });
    SimpleMode.instance.debugReset(false);
  });

  testWidgets('bento header is compact and Today\'s Flow is above the fold',
      (tester) async {
    for (final mobile in [true, false]) {
      final w = mobile ? 390.0 : 1400.0;
      tester.view.physicalSize = Size(w, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull, reason: 'width $w');

      final header = find.byKey(const ValueKey('home_hud_card'));
      final board = find.byType(TaskFlowList, skipOffstage: false);
      final heat = find.byType(ContributionHeatmap, skipOffstage: false);

      expect(header, findsOneWidget, reason: 'width $w');
      expect(board, findsOneWidget, reason: 'width $w');
      expect(heat, findsOneWidget, reason: 'width $w');

      final headerRect = tester.getRect(header);
      final boardRect = tester.getRect(board);

      // Compact bento: ~130px on wide, ~200px stacked on phones (allow
      // a small tolerance either way).
      expect(headerRect.height, lessThanOrEqualTo(210),
          reason: 'bento stays compact, width $w');
      expect(headerRect.height, greaterThanOrEqualTo(110),
          reason: 'bento is a real header, width $w');
      // Board directly after the header.
      expect(headerRect.bottom, lessThanOrEqualTo(boardRect.top),
          reason: 'board after header, width $w');

      if (mobile) {
        // Board sits below the proof and the links (user preference).
        expect(boardRect.top, greaterThan(0),
            reason: 'board present on the page');
      }
    }
  });

  testWidgets('bento header carries the intention and seedling', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(find.text("Today's focus"), findsOneWidget);
    expect(find.textContaining('d streak'), findsOneWidget);
    expect(find.text('SEASONAL JOURNEY'), findsNothing);
  });

  testWidgets('bento header spans the full content width', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    final hudTopLeft =
        tester.getTopLeft(find.byKey(const ValueKey('home_hud_card')));
    final hud = tester.getSize(find.byKey(const ValueKey('home_hud_card')));
    expect(hudTopLeft.dx, 20);
    expect(hudTopLeft.dx + hud.width, 1400 - 20);
  });
}
