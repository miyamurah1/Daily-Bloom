import 'dart:io';

import 'package:daily_bloom/screens/folder_detail_screen.dart';
import 'package:daily_bloom/data/api_client.dart';
import 'package:daily_bloom/widgets/daily_bloom_app_bar.dart';
import 'package:daily_bloom/widgets/sakura_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Code-level accessibility pass (TalkBack/VoiceOver behavior itself
// needs a real device): every icon-only control must declare a role +
// label. Asserted at the widget layer — no semantics handles needed.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('bottom nav tabs declare labelled buttons', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            bottomNavigationBar: SakuraBottomNav(
                currentIndex: 0, onTap: (_) {}))));
    await tester.pump();
    expect(tester.takeException(), isNull);
    for (final label in SakuraBottomNav.labels) {
      expect(
          find.byWidgetPredicate((w) =>
              w is Semantics &&
              (w.properties.button ?? false) &&
              w.properties.label == label),
          findsOneWidget,
          reason: '$label is a labelled button');
    }
    // Icons stay decorative (no double announcement).
    expect(find.byType(ExcludeSemantics), findsWidgets);
  });

  testWidgets('token pill announces its purpose', (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Scaffold(appBar: DailyBloomAppBar())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            (w.properties.button ?? false) &&
            (w.properties.label ?? '').contains('tokens')),
        findsOneWidget);
  });

  testWidgets('back chevrons carry tooltips', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: FolderDetailScreen(
            folder: BloomFolder(name: 'Productivity'))));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    expect(
        find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Back'),
        findsOneWidget);
  });

  // Source-level guard: an icon-only button with no label is invisible
  // to TalkBack/VoiceOver. Every IconButton must declare `tooltip:`
  // (which Material also uses as its semantics label), wrap its icon in
  // a Tooltip, or give the Icon a `semanticLabel`. Walks lib/ directly
  // so new screens can't quietly regress.
  test('every IconButton declares a label', () {
    final offenders = <String>[];
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: 'run from the repo root');
    for (final file in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('IconButton(')) continue;
        // The button's full statement spans several lines; scan a
        // generous window and allow any of the three labelling routes.
        final window = lines.skip(i).take(14).join('\n');
        final labelled = window.contains('tooltip:') ||
            window.contains('Tooltip(') ||
            window.contains('semanticLabel');
        if (!labelled) {
          offenders.add('${file.path}: line ${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'IconButtons without tooltip/semanticLabel '
            '(invisible to screen readers): $offenders');
  });

  // Same guard for icon-only GestureDetectors — a bare icon with a tap
  // handler and no label is announced as nothing by screen readers.
  test('icon-only GestureDetectors carry a label', () {
    final offenders = <String>[];
    final lib = Directory('lib');
    for (final file in lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('GestureDetector(')) continue;
        final window = lines.skip(i).take(12).join('\n');
        final iconOnly = RegExp(r'child:\s*Icon\(').hasMatch(window) ||
            RegExp(r'child:\s*Container\([^)]*Icon\(').hasMatch(window);
        if (!iconOnly) continue;
        final labelled = window.contains('Semantics(') ||
            window.contains('semanticLabel') ||
            window.contains('Tooltip(');
        if (!labelled) {
          offenders.add('${file.path}: line ${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Icon-only GestureDetectors without Semantics: '
            '$offenders');
  });
}
