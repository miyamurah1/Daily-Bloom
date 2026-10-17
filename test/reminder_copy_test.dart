import 'package:daily_bloom/data/reminders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    ReminderService.instance.debugFill();
  });

  group('daily nudge copy', () {
    test('is streak-aware', () {
      expect(ReminderService.dailyBody(0),
          'One small task today keeps the streak alive.');
      expect(ReminderService.dailyBody(7),
          'Day 7 — your garden is waiting.');
    });
  });

  test('setTime persists the hour and clamps the range', () async {
    final svc = ReminderService.instance;
    await svc.setTime(21);
    expect(svc.hour, 21);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('bloom_reminder_hour_v1'), 21);

    await svc.setTime(99);
    expect(svc.hour, 23);

    // A fresh boot reads the last saved hour back.
    svc.debugFill();
    await svc.load();
    expect(svc.hour, 23);
  });

  test('weekly toggle persists and refuses headless (no permission)',
      () async {
    final svc = ReminderService.instance;
    await svc.load();
    expect(svc.weeklyEnabled, isFalse);
    // Headless: no permission channel — enabling is honestly refused.
    expect(await svc.setWeekly(true), isFalse);
    expect(svc.weeklyEnabled, isFalse);
    // Disabling a never-on switch is always allowed.
    expect(await svc.setWeekly(false), isTrue);
    expect(svc.weeklyEnabled, isFalse);
  });

  test('review payload stash drains once (section + task keys)',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bloom_notif_section', 'review');
    await prefs.setString('bloom_notif_task', 't-42');

    expect(await ReminderService.drainNotifSection(), 'review');
    // Single-shot: the second read finds nothing.
    expect(await ReminderService.drainNotifSection(), isNull);

    expect(await ReminderService.drainNotifTask(), 't-42');
    expect(await ReminderService.drainNotifTask(), isNull);
  });

  test('done-action stash drains once and ignores blanks', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(await ReminderService.drainNotifDone(), isNull);

    await prefs.setString('bloom_notif_done', 't-7');
    expect(await ReminderService.drainNotifDone(), 't-7');
    // Single-shot: consumed on the first read.
    expect(await ReminderService.drainNotifDone(), isNull);

    await prefs.setString('bloom_notif_done', '');
    expect(await ReminderService.drainNotifDone(), isNull);
  });

  group('notification action ids', () {
    test('are stable wire values (native round-trips them verbatim)',
        () {
      expect(kNotifActionDone, 'bloom_done');
      expect(kNotifActionPlant, 'bloom_plant');
      expect(kNotifCategoryTaskDue, isNot(kNotifCategoryDailyNudge));
    });
  });
}
