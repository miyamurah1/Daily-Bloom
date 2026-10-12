import 'package:shared_preferences/shared_preferences.dart';

import '../game/daily_intention.dart';
import '../game/first_week_arc.dart';
import '../game/gamification_state.dart';
import '../game/token_economy.dart';
import '../theme/sakura_theme.dart';
import 'energy_store.dart';
import 'goal_store.dart';
import 'habit_store.dart';
import 'inbox_store.dart';
import 'reminders.dart';
import 'task_repository.dart';

/// Per-account prefs keys. Every store persists under a global key, so a
/// new login would otherwise inherit the previous account's tasks, XP,
/// habits and plans (the "new account shows old data" bug).
/// Device-level prefs (ambient toggle, reminder master switch, crash
/// reports) are intentionally absent — they belong to the phone, not the
/// account.
const accountScopedKeys = <String>[
  // Tasks + offline outbox (owned by TaskRepository, removed again in
  // clearForAccountSwitch — listed here so the inventory stays complete).
  'bloom_tasks_cache_v2',
  'bloom_outbox_v1',
  'bloom_outbox_dead_v1',
  // Rituals + project goals.
  'bloom_habits_v1',
  'bloom_project_goals_v1',
  // Energy labels.
  'bloom_energy_v1',
  // Gamification.
  'bloom_game_xp',
  'bloom_game_tokens',
  'bloom_game_streak',
  'bloom_game_last_day',
  'bloom_game_stake_day',
  'bloom_game_stake_ids',
  'bloom_game_wilted',
  'bloom_game_last_stake_loss',
  'bloom_game_wilt_streak',
  'bloom_game_done_day',
  'bloom_game_done_count',
  'bloom_game_nudged_day',
  'bloom_eco_total_earned',
  'bloom_eco_total_spent',
  // Onboarding + one-shot UI flags (new account replays the intro).
  'bloom_onboarding_seen_v1',
  'bloom_concept_seen_v1',
  'bloom_currency_seen_v1',
  // Home planner leftovers.
  'bloom_last_plan_ids',
  'bloom_habit_nudge_day',
];

/// Wipe every per-account trace from the device and reset all in-memory
/// singletons to first-install state. Called on logout, on account switch
/// (different Firebase identity) and after a successful signup.
///
/// Best-effort throughout: a failing store must never block the wipe or
/// strand the user. Offline-first is preserved — empty state simply syncs
/// from the backend on the next successful firebase-sync.
Future<void> clearAccountData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    for (final key in accountScopedKeys) {
      try {
        await prefs.remove(key);
      } catch (_) {}
    }
  } catch (_) {}
  // Cancel OS alarms pointing at the old account's tasks.
  try {
    await ReminderService.instance.cancelAllTaskReminders();
  } catch (_) {}
  // Stores: disk is already clean; these drop in-memory state (several
  // load()s keep stale memory when their key is missing, so reloads
  // alone would not suffice).
  try {
    await TaskRepository.instance.clearForAccountSwitch();
  } catch (_) {}
  try {
    await HabitStore.instance.load();
  } catch (_) {}
  try {
    await GoalStore.instance.resetForNewAccount();
  } catch (_) {}
  try {
    await EnergyStore.instance.resetForNewAccount();
  } catch (_) {}
  try {
    await TokenEconomyManager.instance.load();
  } catch (_) {}
  try {
    GamificationStateNotifier.instance.resetForNewAccount();
  } catch (_) {}
  try {
    await FirstWeekArc.instance.resetForNewAccount();
  } catch (_) {}
  try {
    await DailyIntentionNotifier.instance.clearCustomTarget();
  } catch (_) {}
  try {
    InboxStore.instance.setUnread(0);
  } catch (_) {}
  // Back to the default skin; the new account's equipped theme syncs
  // from the backend on login (ThemeStore.sync in the login flow).
  try {
    ThemeStore.instance.resetToDefault();
  } catch (_) {}
}
