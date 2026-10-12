// Undo must revoke XP: done → undo → done must not mint XP.
// Reopening a task takes back exactly what its completion granted,
// breaks the combo chain and walks back today's completion count.
import 'package:daily_bloom/game/gamification_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late GamificationStateNotifier game;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    game = GamificationStateNotifier();
  });

  tearDown(() => game.dispose());

  test('undo revokes the exact gain of the same task', () {
    final gain = game.registerTaskCompletion(taskId: 'a');
    expect(game.totalXp, gain);
    final revoked = game.revokeTaskCompletion(taskId: 'a');
    expect(revoked, gain);
    expect(game.totalXp, 0);
  });

  test('done-undo-done loop cannot farm XP', () {
    var totalGranted = 0;
    for (var i = 0; i < 3; i++) {
      totalGranted += game.registerTaskCompletion(taskId: 'a');
      game.revokeTaskCompletion(taskId: 'a');
    }
    expect(game.totalXp, 0);
    expect(totalGranted, greaterThan(0));
  });

  test('undo breaks the combo chain', () {
    game.registerTaskCompletion(taskId: 'a');
    expect(game.comboCount, 1);
    game.revokeTaskCompletion(taskId: 'a');
    expect(game.comboCount, 0);
    // Next completion restarts at x1, not x2.
    game.registerTaskCompletion(taskId: 'b');
    expect(game.comboCount, 1);
  });

  test('undo of another task falls back to the base amount', () {
    final gainA = game.registerTaskCompletion(taskId: 'a');
    game.registerTaskCompletion(taskId: 'b');
    final before = game.totalXp;
    expect(before, greaterThan(gainA));
    game.revokeTaskCompletion(taskId: 'a');
    // Only the base grant is taken back; the combo bonus stays honest.
    expect(game.totalXp, lessThan(before));
    expect(game.totalXp, greaterThanOrEqualTo(0));
  });

  test('revoke floors at zero and walks back the daily count', () {
    expect(game.todayCompletions, 0);
    game.registerTaskCompletion(taskId: 'a');
    expect(game.todayCompletions, 1);
    game.revokeTaskCompletion(taskId: 'unrelated');
    game.revokeTaskCompletion(taskId: 'unrelated');
    expect(game.totalXp, 0);
    expect(game.todayCompletions, 0);
  });
}
