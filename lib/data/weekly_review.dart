import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'habit_store.dart';
import 'mock_data.dart';

/// One week in review: Mon–Sun numbers with a single honest verdict.
///
/// Pure data + [buildWeeklyReview] — no widgets, no IO — so the math is
/// unit-testable and both the screen and future callers share it.
/// A week with nothing logged is not an error: [isEmpty] drives the
/// guided empty state ("no signal yet") instead of fake zeros dressed
/// up as insight.
@immutable
class WeeklyReview {
  final DateTime weekStart;
  final DateTime weekEnd;
  final int doneCount;
  final int focusMinutes;
  final int focusSessions;
  final int activeDays;
  final String? bestDay;
  final int bestDayCount;
  final String? topTag;
  final double topTagRate;
  final int habitsKept;
  final int habitsTotal;
  final int streakCurrent;
  final int streakBest;
  final String verdict;

  const WeeklyReview({
    required this.weekStart,
    required this.weekEnd,
    this.doneCount = 0,
    this.focusMinutes = 0,
    this.focusSessions = 0,
    this.activeDays = 0,
    this.bestDay,
    this.bestDayCount = 0,
    this.topTag,
    this.topTagRate = 0,
    this.habitsKept = 0,
    this.habitsTotal = 0,
    this.streakCurrent = 0,
    this.streakBest = 0,
    this.dailyCounts = const [],
    required this.verdict,
  });

  /// Completions per weekday (Mon→Sun). Powers the share card's
  /// week-bloom; empty for reviews built before this field existed.
  final List<int> dailyCounts;

  bool get isEmpty =>
      doneCount == 0 && focusMinutes == 0 && habitsKept == 0;
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Monday 00:00 of the week containing [now].
DateTime reviewWeekStart([DateTime? now]) {
  final d = now ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: d.weekday - 1));
}

/// "Mar 3 – Mar 9" label for the week containing [now].
String reviewWeekLabel([DateTime? now]) {
  final mon = reviewWeekStart(now);
  final sun = mon.add(const Duration(days: 6));
  String fmt(DateTime d) => '${_months[d.month - 1]} ${d.day}';
  return '${fmt(mon)} – ${fmt(sun)}';
}

/// Fold done tasks + insights + habit logs into one weekly verdict.
/// [done] should be completed tasks (any range — only this week counts).
WeeklyReview buildWeeklyReview({
  required List<Task> done,
  required Insights ins,
  required List<Habit> habits,
  DateTime? now,
}) {
  final mon = reviewWeekStart(now);
  final sun = mon.add(const Duration(days: 6));
  final nextMon = mon.add(const Duration(days: 7));
  bool inWeek(DateTime d) =>
      !d.isBefore(mon) && d.isBefore(nextMon);

  // Completions inside the week, grouped by day.
  final byDay = <String, int>{};
  var doneCount = 0;
  for (final t in done) {
    final c = t.completedAt;
    if (c == null) continue;
    final local = c.toLocal();
    if (!inWeek(local)) continue;
    doneCount++;
    final key = HabitStore.dayKey(local);
    byDay[key] = (byDay[key] ?? 0) + 1;
  }
  String? bestDay;
  var bestDayCount = 0;
  final daily = List<int>.filled(7, 0);
  for (var i = 0; i < 7; i++) {
    final d = mon.add(Duration(days: i));
    final n = byDay[HabitStore.dayKey(d)] ?? 0;
    daily[i] = n;
    if (n > bestDayCount) {
      bestDayCount = n;
      bestDay = _weekdays[i];
    }
  }

  // Active days: completion days ∪ focused days.
  final active = <String>{...byDay.keys};
  for (final f in ins.focusDays) {
    if (f.minutes <= 0) continue;
    final parsed = DateTime.tryParse(f.date);
    if (parsed == null) continue;
    final local = DateTime(parsed.year, parsed.month, parsed.day);
    if (inWeek(local)) active.add(HabitStore.dayKey(local));
  }

  // Strongest tag with at least one finished task.
  String? topTag;
  var topTagRate = 0.0;
  final rated = ins.byTag.where((s) => s.done > 0).toList()
    ..sort((a, b) => b.rate.compareTo(a.rate));
  if (rated.isNotEmpty) {
    topTag = rated.first.name;
    topTagRate = rated.first.rate;
  }

  // Kept habits: done on 4+ of the week's 7 days (paused excluded —
  // a paused habit is a choice, not a kept promise).
  final live = habits.where((h) => !h.paused).toList();
  var kept = 0;
  for (final h in live) {
    var days = 0;
    for (var i = 0; i < 7; i++) {
      if (h.doneOn(HabitStore.dayKey(mon.add(Duration(days: i))))) {
        days++;
      }
    }
    if (days >= 4) kept++;
  }

  final verdict = _verdict(
    doneCount: doneCount,
    focusMinutes: ins.focusMinutes7,
    activeDays: active.length,
    bestDay: bestDay,
    bestDayCount: bestDayCount,
    topTag: topTag,
    topTagRate: topTagRate,
    habitsKept: kept,
    habitsTotal: live.length,
  );

  return WeeklyReview(
    weekStart: mon,
    weekEnd: sun,
    doneCount: doneCount,
    focusMinutes: ins.focusMinutes7,
    focusSessions: ins.focusSessions7,
    activeDays: active.length,
    bestDay: bestDay,
    bestDayCount: bestDayCount,
    topTag: topTag,
    topTagRate: topTagRate,
    habitsKept: kept,
    habitsTotal: live.length,
    streakCurrent: ins.streakCurrent,
    streakBest: ins.streakBest30,
    dailyCounts: daily,
    verdict: verdict,
  );
}

String _verdict({
  required int doneCount,
  required int focusMinutes,
  required int activeDays,
  required String? bestDay,
  required int bestDayCount,
  required String? topTag,
  required double topTagRate,
  required int habitsKept,
  required int habitsTotal,
}) {
  if (doneCount == 0 && focusMinutes == 0 && habitsKept == 0) {
    return 'No signal yet — finish a task or run a timer and this page will have a story to tell.';
  }
  final parts = <String>[
    '$doneCount done',
    '$focusMinutes min focused',
    '$activeDays active day${activeDays == 1 ? '' : 's'}',
  ];
  var out = '${parts.join(' · ')}.';
  if (bestDay != null && bestDayCount >= 2) {
    out += ' $bestDay carried the week ($bestDayCount).';
  } else if (topTag != null) {
    out += ' $topTag led at ${(100 * topTagRate).round()}%.';
  }
  if (habitsTotal > 0) {
    out += habitsKept == habitsTotal
        ? ' Every habit kept.'
        : ' $habitsKept of $habitsTotal habits kept.';
  }
  return out;
}
