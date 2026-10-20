// Simple Mode: the calm default that hides power-tool doors without
// removing them. Verifies persistence and the Home quick-link adaption.
import 'package:daily_bloom/data/simple_mode.dart';
import 'package:daily_bloom/screens/home_screen.dart';
import 'package:daily_bloom/theme/sakura_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpHome(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  await tester.pump();
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bloom_concept_seen_v1': true,
      'bloom_simple_mode_v1': false,
    });
    SakuraTheme.useGoogleFonts = false;
  });

  test('toggling persists to SharedPreferences', () async {
    await SimpleMode.instance.setEnabled(true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('bloom_simple_mode_v1'), true);
    await SimpleMode.instance.setEnabled(false);
    expect(prefs.getBool('bloom_simple_mode_v1'), false);
  });

  testWidgets('full mode shows the Board door', (tester) async {
    SimpleMode.instance.debugReset(false);
    await _pumpHome(tester);
    expect(find.text('BOARD \u2192', skipOffstage: false), findsOneWidget);
    expect(find.text('HISTORY \u2192', skipOffstage: false), findsOneWidget);
  });

  testWidgets('simple mode hides the power doors but keeps the page usable',
      (tester) async {
    SimpleMode.instance.debugReset(true);
    await _pumpHome(tester);
    expect(find.text('BOARD \u2192', skipOffstage: false), findsNothing,
        reason: 'power tool hidden, not deleted');
    expect(find.text('HISTORY \u2192', skipOffstage: false), findsNothing,
        reason: 'quick links are an Advanced surface');
    expect(find.text("Today's focus"), findsOneWidget);
  });
}
