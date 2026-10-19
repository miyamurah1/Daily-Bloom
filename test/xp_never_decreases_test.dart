import 'package:daily_bloom/game/bloom_engine.dart';
import 'package:daily_bloom/game/gamification_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The brand promise, as an executable test: XP never decreases except
/// by an explicit undo, and the removed stake/wilt system leaves no
/// trace. A quiet garden is a resting garden — never a punished one.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('XP only grows — completions and rituals never lose', () {
    final game = GamificationStateNotifier();
    game.addXp(500);
    game.registerTaskCompletion();
    game.claimDailyRitual();
    game.markDailyActive();
    // Nothing here may subtract: the only downward path is the undo API.
    expect(game.totalXp, greaterThan(500));
  });

  test('daily rollover never deducts XP', () {
    final game = GamificationStateNotifier();
    game.addXp(500);
    // Simulate days passing with zero activity — the old stake system
    // would have wilted and deducted here.
    game.markDailyActive(DateTime.now().subtract(const Duration(days: 3)));
    game.markDailyActive();
    expect(game.totalXp, 500);
  });

  test('undo is the only downward path and floors at zero', () {
    final game = GamificationStateNotifier();
    game.registerTaskCompletion();
    final afterFirst = game.totalXp;
    expect(afterFirst, greaterThan(0));
    game.revokeTaskCompletion();
    expect(game.totalXp, afterFirst - BloomEngine.baseTaskXp);
    // Repeated undos floor at zero — never negative.
    game.revokeTaskCompletion();
    game.revokeTaskCompletion();
    expect(game.totalXp, 0);
  });

  test('legacy stake/wilt prefs are purged on load', () async {
    SharedPreferences.setMockInitialValues({
      'bloom_game_xp': 300,
      'bloom_game_stake_day': '2026-01-01',
      'bloom_game_stake_ids': ['a', 'b'],
      'bloom_game_wilted': true,
      'bloom_game_last_stake_loss': 10,
      'bloom_game_wilt_streak': 2,
    });
    final game = GamificationStateNotifier();
    await game.load();
    expect(game.totalXp, 300); // XP survives the migration
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('bloom_game_stake_day'), isNull);
    expect(prefs.getStringList('bloom_game_stake_ids'), isNull);
    expect(prefs.getBool('bloom_game_wilted'), isNull);
    expect(prefs.getInt('bloom_game_last_stake_loss'), isNull);
    expect(prefs.getInt('bloom_game_wilt_streak'), isNull);
  });

  test('there is no stake or wilt API left to call', () {
    final game = GamificationStateNotifier();
    // The public surface must not expose punishment primitives. If any
    // of these compile again, the brand promise is broken.
    expect(() => (game as dynamic).stakeDay, throwsNoSuchMethodError);
    expect(() => (game as dynamic).settleDay, throwsNoSuchMethodError);
    expect(() => (game as dynamic).wilted, throwsNoSuchMethodError);
  });

  test('completions count today, nudge fires once', () {
    final game = GamificationStateNotifier();
    expect(game.todayCompletions, 0);
    game.registerTaskCompletion();
    game.registerTaskCompletion();
    game.registerTaskCompletion();
    expect(game.todayCompletions, 3);
    expect(game.reviewNudgedToday, isFalse);
    game.markReviewNudged();
    expect(game.reviewNudgedToday, isTrue);
  });
}