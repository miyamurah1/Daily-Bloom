import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'dart:convert';

import '../game/gamification_state.dart';
import 'mock_data.dart';

/// Payload inbox for notification taps: the background handler stashes
/// the tapped task id (or review section) here (prefs — isolates can't
/// touch widgets) and AppShell drains it on launch/resume to deep-link.
///
/// Action buttons ride the same inbox: a "Done" action stashes
/// `done:<taskId>` (drained into a repo move-to-done) and a "Plant"
/// action stashes the `quickadd` section (drained into quick-add).
const _kNotifTask = 'bloom_notif_task';
const _kNotifSection = 'bloom_notif_section';
const _kNotifDone = 'bloom_notif_done';

/// Action ids for the notification buttons below. Plain lowercase —
/// Android and iOS both round-trip these verbatim in `actionId`.
const kNotifActionDone = 'bloom_done';
const kNotifActionPlant = 'bloom_plant';

/// iOS categories. NOTE: iOS freezes category actions at install —
/// renaming a category after release needs a reinstall or a new id.
const kNotifCategoryTaskDue = 'task_due';
const kNotifCategoryDailyNudge = 'daily_nudge';

Future<void> _stashNotifPayload(String? payload, {String? actionId}) async {
  if (payload == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    // "Done ✓" on a due-date alarm completes the task behind it.
    if (actionId == kNotifActionDone && payload.startsWith('task:')) {
      final id = payload.substring(5);
      if (id.isNotEmpty) await prefs.setString(_kNotifDone, id);
      return;
    }
    // "Plant 🌱" on the daily nudge opens capture (same as tapping it).
    if (actionId == kNotifActionPlant) {
      await prefs.setString(_kNotifSection, 'quickadd');
      return;
    }
    if (payload.startsWith('task:')) {
      await prefs.setString(_kNotifTask, payload.substring(5));
    } else if (payload.startsWith('review')) {
      await prefs.setString(_kNotifSection, 'review');
    } else if (payload.startsWith('quickadd')) {
      await prefs.setString(_kNotifSection, 'quickadd');
    }
  } catch (_) {}
}

@pragma('vm:entry-point')
void onNotifTap(NotificationResponse response) {
  _stashNotifPayload(response.payload, actionId: response.actionId);
}

@pragma('vm:entry-point')
void onNotifBackgroundTap(NotificationResponse response) {
  // Background isolate: stashing only — no repo/plugin access here.
  // The foreground drain completes the task on next launch/resume.
  _stashNotifPayload(response.payload, actionId: response.actionId);
}

/// One gentle daily nudge ("Time to tend your bloom · 9:00").
///
/// Staged, not finished: scheduling + toggle + persistence all work and
/// are unit-safe, but actual firing must be confirmed on a real device
/// (emulators lie about doze/inexact windows). Uses inexact scheduling
/// on purpose — no exact-alarm manifest permission, no Play review flag.
/// Default OFF: the app never prompts for notification permission until
/// the user flips the switch in Settings.
class ReminderService extends ChangeNotifier {
  static const _kEnabled = 'bloom_reminder_v1';
  static const _id = 1;
  static const _focusId = 2;
  static const _reviewId = 3;
  static const _kHour = 'bloom_reminder_hour_v1';
  static const _kWeekly = 'bloom_reminder_review_v1';

  static final ReminderService instance = ReminderService._();
  ReminderService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _enabled = false;
  bool _ready = false;
  int _hour = 9;
  bool _weeklyOn = false;

  bool get enabled => _enabled;

  /// Hour the daily nudge fires (0–23). User-configurable in Settings.
  int get hour => _hour;

  /// The Sunday-evening look-back runs on its own switch.
  bool get weeklyEnabled => _weeklyOn;

  Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation(
            (await FlutterTimezone.getLocalTimezone()).identifier));
      } catch (_) {
        // Fallback keeps scheduling working with a fixed offset.
        tz.setLocalLocation(tz.getLocation('Etc/UTC'));
      }
      // The action factories are not const, so the iOS half of this
      // literal is non-const; the Android half stays a const.
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      final settings = InitializationSettings(
        android: androidInit,
        // iOS action categories: "Done ✓" on due alarms, "Plant 🌱" on
        // the daily nudge. Registered once here (see the frozen-at-install
        // note on the category ids above).
        iOS: DarwinInitializationSettings(
          notificationCategories: [
            DarwinNotificationCategory(
              kNotifCategoryTaskDue,
              actions: [
                DarwinNotificationAction.plain(
                    kNotifActionDone, 'Done ✓'),
              ],
            ),
            DarwinNotificationCategory(
              kNotifCategoryDailyNudge,
              actions: [
                DarwinNotificationAction.plain(
                    kNotifActionPlant, 'Plant 🌱'),
              ],
            ),
          ],
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: onNotifTap,
        onDidReceiveBackgroundNotificationResponse: onNotifBackgroundTap,
      );
      _ready = true;
    } catch (_) {
      // Desktop / test harness: scheduling degrades to a no-op below.
      return;
    }
    // Re-arm after reboot/update: the OS drops scheduled alarms.
    if (_enabled) {
      await scheduleDaily();
    }
    if (_weeklyOn) {
      await scheduleWeekly();
    }
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_kEnabled) ?? false;
      _hour = (prefs.getInt(_kHour) ?? 9).clamp(0, 23);
      _weeklyOn = prefs.getBool(_kWeekly) ?? false;
      notifyListeners();
    } catch (_) {}
  }

  /// Flip the switch. Enabling requests OS permission first — a denial
  /// leaves the toggle off with no scheduled alarm and no nagging.
  Future<bool> setEnabled(bool value) async {
    if (value) {
      final granted = await _requestPermission();
      if (!granted) return false;
      _enabled = true;
      await _persist();
      notifyListeners();
      await scheduleDaily();
      return true;
    }
    _enabled = false;
    await _persist();
    notifyListeners();
    await cancelDaily();
    return true;
  }

  /// Move the daily nudge. Re-arms the alarm immediately when the
  /// reminder is on, so the new hour applies tonight — not tomorrow.
  Future<void> setTime(int hour) async {
    _hour = hour.clamp(0, 23);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kHour, _hour);
    } catch (_) {}
    notifyListeners();
    if (_enabled) await scheduleDaily();
  }

  /// Sunday-evening weekly review nudge. Its own switch: the daily nudge
  /// is a habit prompt, this one is a look-back — different promises.
  /// Enabling requests OS permission first, like the daily toggle.
  Future<bool> setWeekly(bool value) async {
    if (value) {
      final granted = await _requestPermission();
      if (!granted) return false;
      _weeklyOn = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_kWeekly, true);
      } catch (_) {}
      notifyListeners();
      await scheduleWeekly();
      return true;
    }
    _weeklyOn = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kWeekly, false);
    } catch (_) {}
    notifyListeners();
    await cancelWeekly();
    return true;
  }

  /// Copy for the daily nudge — streak-aware so "Day 12" lands harder
  /// than a generic sentence. Static + pure: unit-tested headless.
  @visibleForTesting
  static String dailyBody(int streak) => streak > 0
      ? 'Day $streak — your garden is waiting.'
      : 'One small task today keeps the streak alive.';

  Future<bool> _requestPermission() async {
    try {
      if (kIsWeb) return true;
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> scheduleDaily() async {
    if (!_ready || !_enabled) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      var at = tz.TZDateTime(
          tz.local, now.year, now.month, now.day, _hour);
      if (!at.isAfter(now)) {
        at = at.add(const Duration(days: 1));
      }
      await _plugin.zonedSchedule(
        id: _id,
        title: 'Time to tend your bloom',
        body: dailyBody(GamificationStateNotifier.instance.streak),
        scheduledDate: at,
        // Tap → straight into quick-add: the nudge is actionable.
        // "Plant 🌱" does the same without opening the app first.
        payload: 'quickadd:',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily-bloom',
            'Daily reminder',
            importance: Importance.low,
            priority: Priority.low,
            actions: [
              AndroidNotificationAction(
                  kNotifActionPlant, 'Plant 🌱'),
            ],
          ),
          iOS: DarwinNotificationDetails(
            categoryIdentifier: kNotifCategoryDailyNudge,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (_) {}
  }

  Future<void> cancelDaily() async {
    try {
      await _plugin.cancel(id: _id);
    } catch (_) {}
  }

  /// Sunday-evening look-back: next Sunday at 18:00, repeating weekly.
  /// The `review:` payload drains on tap into the weekly review screen.
  Future<void> scheduleWeekly() async {
    if (!_ready || !_weeklyOn) return;
    try {
      final now = tz.TZDateTime.now(tz.local);
      final daysAhead = (DateTime.sunday - now.weekday) % 7;
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, 18)
          .add(Duration(days: daysAhead));
      if (!at.isAfter(now)) {
        at = at.add(const Duration(days: 7));
      }
      await _plugin.zonedSchedule(
        id: _reviewId,
        title: 'Your week in bloom',
        body: 'A calm look-back: what grew, what wilted, what next.',
        scheduledDate: at,
        payload: 'review:',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily-bloom-review',
            'Weekly review',
            importance: Importance.low,
            priority: Priority.low,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    } catch (_) {}
  }

  Future<void> cancelWeekly() async {
    try {
      await _plugin.cancel(id: _reviewId);
    } catch (_) {}
  }

  /// Focus-timer expiry alarm: fires once at `now + duration`, even when
  /// the app is backgrounded or the screen is locked. Exact when the OS
  /// grants it (falls back to inexact otherwise — still better than the
  /// old silent finish). Re-scheduling replaces the previous alarm, so
  /// pause/resume/±1min just call this again; abandon/finish cancels it.
  ///
  /// Permission is requested here, not at boot: starting a timer is the
  /// user's explicit consent moment. A denial degrades to in-app timing.
  Future<void> scheduleFocusTimerNotification({
    required Duration duration,
    required String label,
  }) async {
    if (!_ready) return;
    final safe = duration.isNegative ? Duration.zero : duration;
    try {
      final granted = await _requestPermission();
      if (!granted) return;
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      var exact = false;
      if (android != null) {
        try {
          exact = await android.canScheduleExactNotifications() ?? false;
          if (!exact) {
            exact =
                await android.requestExactAlarmsPermission() ?? false;
          }
        } catch (_) {
          exact = false;
        }
      }
      final at = tz.TZDateTime.now(tz.local).add(safe);
      await _plugin.zonedSchedule(
        id: _focusId,
        title: '🌸 Focus session complete!',
        body:
            '“$label” — you completed your focus block. Time to take a mindful rest.',
        scheduledDate: at,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'daily-bloom-focus',
            'Focus timer',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  /// Drop the pending expiry alarm (pause, abandon, finish).
  Future<void> cancelFocusTimerNotification() async {
    try {
      await _plugin.cancel(id: _focusId);
    } catch (_) {}
  }

  /// Take a pending notification-tap task id left by the background
  /// handler (or null). Single-shot: the stash clears on read.
  static Future<String?> drainNotifTask() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kNotifTask);
      if (id != null) await prefs.remove(_kNotifTask);
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Take a pending notification-tap section ('review') or null.
  /// Single-shot: the stash clears on read.
  static Future<String?> drainNotifSection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_kNotifSection);
      if (s != null) await prefs.remove(_kNotifSection);
      return (s == null || s.isEmpty) ? null : s;
    } catch (_) {
      return null;
    }
  }

  /// Take a pending "Done ✓" action task id (or null). Single-shot.
  /// The completer moves the task to done via the repository (optimistic
  /// + outboxed, so it works even if the app was killed offline).
  static Future<String?> drainNotifDone() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_kNotifDone);
      if (id != null) await prefs.remove(_kNotifDone);
      return (id == null || id.isEmpty) ? null : id;
    } catch (_) {
      return null;
    }
  }

  static const _kTaskAlarms = 'bloom_task_alarms_v1';

  /// Max dated tasks armed at once (OS limits + sanity).
  static const maxTaskAlarms = 50;

  /// Stable notification id per task id.
  @visibleForTesting
  static int taskAlarmId(String taskId) =>
      taskId.hashCode & 0x7fffffff;

  /// Reconcile per-task due alarms with the board: schedule future
  /// dated open tasks, cancel finished/deleted/retimed ones. Diff-only,
  /// so steady state costs zero platform calls. Past-due tasks are
  /// skipped (the plan surfaces those instead of buzzing about them).
  Future<void> syncTaskReminders(List<Task> tasks) async {
    Map<String, int> prev = {};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTaskAlarms);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          prev = {
            for (final e in decoded.entries)
              '${e.key}': (e.value as num?)?.toInt() ?? 0,
          };
        }
      }
    } catch (_) {}
    final now = DateTime.now();
    final want = <String, int>{};
    final wantTitles = <String, String>{};
    final open = tasks
        .where((t) =>
            t.status != 'done' &&
            t.dueAt != null &&
            t.dueAt!.isAfter(now))
        .toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    for (final t in open.take(maxTaskAlarms)) {
      want[t.id] = t.dueAt!.millisecondsSinceEpoch;
      wantTitles[t.id] = t.title;
    }
    var permissionAsked = false;
    var permitted = false;
    for (final entry in prev.entries) {
      if (want[entry.key] != entry.value) {
        try {
          await _plugin.cancel(id: taskAlarmId(entry.key));
        } catch (_) {}
      }
    }
    for (final entry in want.entries) {
      if (prev[entry.key] == entry.value) continue;
      if (!_ready) continue;
      if (!permissionAsked) {
        permissionAsked = true;
        try {
          permitted = await _requestPermission();
        } catch (_) {
          permitted = false;
        }
      }
      if (!permitted) break;
      try {
        await _scheduleTaskAlarm(
          taskId: entry.key,
          at: DateTime.fromMillisecondsSinceEpoch(entry.value),
          title: wantTitles[entry.key] ?? 'Task due',
        );
      } catch (_) {}
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTaskAlarms, jsonEncode(want));
    } catch (_) {}
  }

  Future<void> _scheduleTaskAlarm({
    required String taskId,
    required DateTime at,
    required String title,
  }) async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    var exact = false;
    if (android != null) {
      try {
        exact = await android.canScheduleExactNotifications() ?? false;
        if (!exact) {
          exact = await android.requestExactAlarmsPermission() ?? false;
        }
      } catch (_) {
        exact = false;
      }
    }
    await _plugin.zonedSchedule(
      id: taskAlarmId(taskId),
      title: 'Due now 🌸',
      body: title,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      payload: 'task:$taskId',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily-bloom-tasks',
          'Task due dates',
          importance: Importance.high,
          priority: Priority.high,
          // "Done ✓" completes the task without opening the app;
          // the plain tap still opens its detail for context.
          actions: [
            AndroidNotificationAction(kNotifActionDone, 'Done ✓'),
          ],
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          categoryIdentifier: kNotifCategoryTaskDue,
        ),
      ),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Drop every task alarm (account logout / wipe).
  Future<void> cancelAllTaskReminders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTaskAlarms);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final k in decoded.keys) {
            try {
              await _plugin.cancel(id: taskAlarmId('$k'));
            } catch (_) {}
          }
        }
      }
      await prefs.remove(_kTaskAlarms);
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, _enabled);
    } catch (_) {}
  }

  @visibleForTesting
  void debugFill({bool enabled = false}) {
    _enabled = enabled;
    _hour = 9;
    _weeklyOn = false;
    notifyListeners();
  }
}
