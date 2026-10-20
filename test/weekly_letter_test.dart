// The weekly "letter": the forward-looking line that turns a stats page
// into meaning. Pure data, so it is unit-testable without widgets.
import 'package:daily_bloom/data/weekly_review.dart';
import 'package:flutter_test/flutter_test.dart';

WeeklyReview _review({
  int doneCount = 0,
  int focusMinutes = 0,
  int habitsKept = 0,
  int habitsTotal = 0,
  String? topTag,
  int streakCurrent = 0,
}) =>
    WeeklyReview(
      weekStart: DateTime(2026, 1, 5),
      weekEnd: DateTime(2026, 1, 11),
      doneCount: doneCount,
      focusMinutes: focusMinutes,
      habitsKept: habitsKept,
      habitsTotal: habitsTotal,
      topTag: topTag,
      streakCurrent: streakCurrent,
      verdict: 'verdict',
    );

void main() {
  test('an empty week invites one small start', () {
    expect(_review().carry, contains('one small thing'));
  });

  test('a habit gap asks to carry one ritual', () {
    final r = _review(doneCount: 3, habitsKept: 1, habitsTotal: 3);
    expect(r.carry, contains('Carry one ritual'));
    expect(r.carry, contains('2 habits'));
  });

  test('a strong tag names the block to protect', () {
    final r = _review(doneCount: 5, topTag: 'Work');
    expect(r.carry, 'Protect one block for Work next week.');
  });

  test('a live streak asks to keep it alive', () {
    final r = _review(doneCount: 2, streakCurrent: 5);
    expect(r.carry, contains('5-day streak'));
  });

  test('falls back to one concrete act when there is no signal', () {
    final r = _review(doneCount: 1);
    expect(r.carry, contains('before noon'));
  });
}
