import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daily_bloom/game/gamification_state.dart';

void main() {
  test('task reward ledger revokes the exact task gain', () async {
    SharedPreferences.setMockInitialValues({});
    final game = GamificationStateNotifier();
    await game.load();

    final first = game.registerTaskCompletion(taskId: 'task-a');
    final second = game.registerTaskCompletion(taskId: 'task-b');
    expect(first, greaterThan(0));
    expect(second, greaterThan(0));

    final beforeUndo = game.totalXp;
    expect(game.revokeTaskCompletion(taskId: 'task-a'), first);
    expect(game.totalXp, beforeUndo - first);

    // A duplicate completion event cannot mint a second reward, including
    // the done → undo → done farming loop.
    expect(game.registerTaskCompletion(taskId: 'task-a'), 0);
    expect(game.registerTaskCompletion(taskId: 'task-b'), 0);
  });
}
