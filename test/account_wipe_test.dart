// Account-switch wipe: a new login must never inherit the previous
// account's tasks, XP, habits, goals or plans. All stores persist under
// global prefs keys, so AuthStore wipes them on logout / account switch /
// signup via clearAccountData().
import 'package:daily_bloom/data/account_wipe.dart';
import 'package:daily_bloom/data/api_client.dart';
import 'package:daily_bloom/data/mock_data.dart';
import 'package:daily_bloom/data/task_repository.dart';
import 'package:daily_bloom/game/gamification_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineApi extends BloomApi {
  @override
  Future<Task> createTask(
    String title, {
    String folder = 'Productivity',
    String tag = 'General',
    String description = '',
    String priority = 'none',
    String recurring = 'none',
    DateTime? dueAt,
    String? clientId,
  }) async {
    throw Exception('offline');
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'bloom_tasks_cache_v2': '[]',
      'bloom_outbox_v1': '[]',
      'bloom_habits_v1': '{"goals":[],"habits":[]}',
      'bloom_project_goals_v1': '{"goals":[]}',
      'bloom_energy_v1': '{"old-task":"high"}',
      'bloom_game_xp': 98,
      'bloom_game_tokens': 12,
      'bloom_game_streak': 4,
      'bloom_eco_total_earned': 200,
      'bloom_onboarding_seen_v1': true,
      'bloom_last_plan_ids': '["old-task"]',
    });
    TaskRepository.apiFactory = _OfflineApi.new;
    TaskRepository.autoRetry = false;
  });

  tearDown(() {
    TaskRepository.autoRetry = true;
  });

  test('clearAccountData drops stale per-account state', () async {
    // Previous account's in-memory life.
    await TaskRepository.instance.createTask(title: 'Old task');
    expect(TaskRepository.instance.tasks, isNotEmpty);
    expect(TaskRepository.instance.pendingMutations, 1);
    GamificationStateNotifier.instance.addXp(50);
    expect(GamificationStateNotifier.instance.totalXp, greaterThan(0));

    await clearAccountData();

    final prefs = await SharedPreferences.getInstance();
    for (final key in accountScopedKeys) {
      // Resets may persist fresh defaults (0/false) back to disk — what
      // must not survive is the previous account's *values*.
      final value = prefs.get(key);
      final isFresh = value == null ||
          value == 0 ||
          value == false ||
          value == '' ||
          (value is List && value.isEmpty);
      expect(isFresh, isTrue, reason: 'stale $key=$value survived the wipe');
    }
    expect(TaskRepository.instance.tasks, isEmpty);
    expect(TaskRepository.instance.pendingMutations, 0);
    expect(GamificationStateNotifier.instance.totalXp, 0);
    expect(GamificationStateNotifier.instance.streak, 0);
  });
}
