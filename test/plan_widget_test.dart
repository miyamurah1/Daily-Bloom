import 'package:daily_bloom/data/plan_widget.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses task + plan taps, rejects the rest', () {
    expect(
      PlanWidgetBridge.parsePlanWidgetUri(Uri.parse('dailybloom://task/abc')),
      (type: 'task', id: 'abc'),
    );
    expect(
      PlanWidgetBridge.parsePlanWidgetUri(Uri.parse('dailybloom://plan')),
      (type: 'plan', id: null),
    );
    expect(PlanWidgetBridge.parsePlanWidgetUri(Uri.parse('dailybloom://nope')), isNull);
    expect(PlanWidgetBridge.parsePlanWidgetUri(Uri.parse('https://x.test/task/a')), isNull);
    expect(PlanWidgetBridge.parsePlanWidgetUri(null), isNull);
  });

  test('push degrades to false off-device', () async {
    // Tests run on a non-mobile platform with no plugin host.
    expect(await PlanWidgetBridge.pushPlan(const []), isFalse);
    expect(await PlanWidgetBridge.initialLaunchUri(), isNull);
  });

  group('launcher stats line', () {
    test('combines streak + progress', () {
      expect(
        PlanWidgetBridge.formatStats(streak: 12, done: 2, open: 3),
        'Day 12 · 2 done · 3 open',
      );
    });

    test('omits the streak when there is none', () {
      expect(
        PlanWidgetBridge.formatStats(streak: 0, done: 1, open: 2),
        '1 done · 2 open',
      );
    });

    test('is empty (row hidden) when nothing is known', () {
      expect(
        PlanWidgetBridge.formatStats(streak: 0, done: 0, open: 0),
        isEmpty,
      );
    });
  });
}
