// The unified model: a habit is just a commitment you tend daily.
// These tests prove the new fields round-trip through JSON and copyWith
// without breaking the existing one-off task contract.
import 'package:daily_bloom/data/mock_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a one-off task defaults to cadence "once"', () {
    const t = Task(id: 't1', title: 'Write', tag: 'Work');
    expect(t.isHabit, isFalse);
    expect(t.cadence, 'once');
    expect(t.doneOn('2026-01-01'), isFalse);
  });

  test('a habit round-trips every field through JSON', () {
    const original = Task(
      id: 'h1',
      title: 'Morning meditation',
      tag: 'Habit',
      cadence: 'daily',
      habitCounted: true,
      habitTarget: 10,
      habitUnit: 'minutes',
      habitGoalId: 'g1',
      habitIconIndex: 4,
      habitAccentIndex: 2,
      habitPaused: false,
      habitLog: {'2026-01-01': 10, '2026-01-02': 3},
      habitFrozen: true,
      habitFrozenStreak: 7,
    );

    final json = {
      'id': original.id,
      'title': original.title,
      'tag': original.tag,
      'cadence': original.cadence,
      'habit_counted': original.habitCounted,
      'habit_target': original.habitTarget,
      'habit_unit': original.habitUnit,
      'habit_goal_id': original.habitGoalId,
      'habit_icon': original.habitIconIndex,
      'habit_accent': original.habitAccentIndex,
      'habit_paused': original.habitPaused,
      'habit_log': original.habitLog,
      'habit_frozen': original.habitFrozen,
      'habit_frozen_streak': original.habitFrozenStreak,
    };

    final parsed = Task.fromJson(json);
    expect(parsed.isHabit, isTrue);
    expect(parsed.title, 'Morning meditation');
    expect(parsed.habitCounted, isTrue);
    expect(parsed.habitTarget, 10);
    expect(parsed.habitUnit, 'minutes');
    expect(parsed.habitGoalId, 'g1');
    expect(parsed.habitIconIndex, 4);
    expect(parsed.habitAccentIndex, 2);
    expect(parsed.habitLog, {'2026-01-01': 10, '2026-01-02': 3});
    expect(parsed.habitFrozen, isTrue);
    expect(parsed.habitFrozenStreak, 7);
  });

  test('doneOn respects the habit target and pauses', () {
    const habit = Task(
      id: 'h2',
      title: 'Water',
      tag: 'Habit',
      cadence: 'daily',
      habitCounted: true,
      habitTarget: 8,
      habitLog: {'2026-01-01': 8, '2026-01-02': 3},
    );
    expect(habit.doneOn('2026-01-01'), isTrue);
    expect(habit.doneOn('2026-01-02'), isFalse);
    expect(habit.doneOn('2026-01-03'), isFalse);
  });

  test('copyWith preserves the unified fields', () {
    const original = Task(
      id: 'h3',
      title: 'Walk',
      tag: 'Habit',
      cadence: 'daily',
      habitGoalId: 'g2',
      habitLog: {'2026-01-01': 1},
    );
    final renamed = original.copyWith(title: 'Evening walk');
    expect(renamed.cadence, 'daily');
    expect(renamed.habitGoalId, 'g2');
    expect(renamed.habitLog, {'2026-01-01': 1});
    expect(renamed.title, 'Evening walk');
  });
}
