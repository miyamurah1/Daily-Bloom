import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/haptics.dart';
import 'bloom_engine.dart';

/// Single source of truth for Mindful Gamification.
///
/// Holds XP, tokens, streak, rank, and the Flow Combo timer. Pair with
/// `ListenableBuilder` (the app's existing pattern) — no Riverpod needed.
///
/// ```dart
/// final game = GamificationStateNotifier();
/// await game.load();
/// ListenableBuilder(
///   listenable: game,
///   builder: (c, _) => Text('Lv ${game.level} · ${game.tokens}◆'),
/// );
/// game.registerTaskCompletion(); // +XP, advances combo
/// ```
class GamificationStateNotifier extends ChangeNotifier {
  static const _kXp = 'bloom_game_xp';
  static const _kTokens = 'bloom_game_tokens';
  static const _kStreak = 'bloom_game_streak';
  static const _kLastDay = 'bloom_game_last_day';
  static const _kStakeDay = 'bloom_game_stake_day';
  static const _kStakeIds = 'bloom_game_stake_ids';
  static const _kWilted = 'bloom_game_wilted';
  static const _kLastStakeLoss = 'bloom_game_last_stake_loss';
  static const _kWiltStreak = 'bloom_game_wilt_streak';
  static const _kDoneDay = 'bloom_game_done_day';
  static const _kDoneCount = 'bloom_game_done_count';
  static const _kNudgedDay = 'bloom_game_nudged_day';

  /// App-wide singleton — screens share one combo / XP / streak.
  static final GamificationStateNotifier instance =
      GamificationStateNotifier();

  int _totalXp = 0;
  int _tokens = 0;
  int _streak = 0;
  String? _lastDayIso;

  /// Today's stake: task ids planned via Plan-my-day, each risking
  /// [BloomEngine.stakePerTask] XP if unfinished at rollover.
  String? _stakedDayIso;
  List<String> _stakedIds = const [];

  /// True after a morning wilt, cleared by the next completion.
  bool _wilted = false;
  int _lastStakeLoss = 0;

  /// Consecutive mornings with a wilt. At 2+, the next settle is
  /// forgiven (rest mode) — compassion as a rule, not a sentence.
  int _wiltStreak = 0;

  /// Completions today (for the after-3rd review nudge) + the day the
  /// nudge last fired, so it suggests once, never nags.
  String? _doneDayIso;
  int _doneCount = 0;
  String? _nudgedDayIso;

  DateTime? _lastCompletionAt;
  int _comboCount = 0;
  DateTime? _comboExpiresAt;
  Timer? _comboTimer;

  /// Undo support: gain + task of the most recent completion, so reopening
  /// that task revokes exactly what it granted. Memory-only: after a
  /// restart an undo falls back to the base amount.
  String? _lastGainTaskId;
  int? _lastGain;

  final Random _random;

  GamificationStateNotifier({Random? random}) : _random = random ?? Random();

  // --- Reads (cheap getters, safe to call in build) ---

  int get totalXp => _totalXp;
  int get tokens => _tokens;
  int get streak => _streak;

  /// Wired in main(): lets the daily-reminder copy follow the live streak
  /// without the game layer importing notifications (no import cycles).
  static void Function()? onStreakChanged;

  int get level => BloomEngine.levelForTotalXp(_totalXp);
  double get levelProgress => BloomEngine.progressInLevel(_totalXp);
  int get xpIntoLevel => _totalXp - BloomEngine.totalXpForLevel(level);
  int get xpNeeded => BloomEngine.xpToNext(level);

  BloomRank get rank => BloomEngine.rankForLevel(level);
  String get rankName => BloomEngine.rankName(rank);

  /// Live combo, 0 when expired. Never goes stale: expiry fires notify.
  int get comboCount {
    final exp = _comboExpiresAt;
    if (exp != null && DateTime.now().isAfter(exp)) return 0;
    return _comboCount;
  }

  bool get isComboLive => comboCount > 0;
  DateTime? get comboExpiresAt => _comboExpiresAt;

  /// Day-key the current stake belongs to, null when nothing staked.
  String? get stakedDayIso => _stakedDayIso;

  /// Task ids at stake today (max 3, latest plan wins).
  List<String> get stakedIds => List.unmodifiable(_stakedIds);

  /// True after a morning wilt — cleared by the next completion.
  bool get wilted => _wilted;

  /// XP lost in the most recent settle (0 when all kept).
  int get lastStakeLoss => _lastStakeLoss;

  /// Consecutive mornings with a wilt. At 2+, tonight is free.
  int get wiltStreak => _wiltStreak;

  /// Completions so far today (resets at midnight).
  int get todayCompletions {
    if (_doneDayIso != _dayKey(DateTime.now())) return 0;
    return _doneCount;
  }

  /// Whether the review nudge already fired today.
  bool get reviewNudgedToday =>
      _nudgedDayIso == _dayKey(DateTime.now());

  /// Mark the review nudge as shown for today.
  void markReviewNudged() {
    _nudgedDayIso = _dayKey(DateTime.now());
    _persist();
    notifyListeners();
  }

  // --- Writes ---

  /// Call when a task is completed. Returns the XP granted (incl. bonus).
  /// Chains completions inside [BloomEngine.comboWindow] into a combo.
  /// Pass the task id so a later undo can revoke exactly what was granted
  /// (anti-farm: done → undo → done must not mint XP).
  int registerTaskCompletion(
      {int baseXp = BloomEngine.baseTaskXp, String? taskId}) {
    final now = DateTime.now();
    final last = _lastCompletionAt;
    if (last != null && now.difference(last) <= BloomEngine.comboWindow) {
      _comboCount++;
    } else {
      _comboCount = 1;
    }
    _lastCompletionAt = now;
    _comboExpiresAt = now.add(BloomEngine.comboWindow);
    _scheduleComboExpiry();

    final day = _dayKey(now);
    if (_doneDayIso == day) {
      _doneCount++;
    } else {
      _doneDayIso = day;
      _doneCount = 1;
    }
    final gain = BloomEngine.xpForCombo(baseXp, _comboCount);
    _totalXp += gain;
    _lastGainTaskId = taskId;
    _lastGain = gain;
    _wilted = false; // a fresh bloom clears yesterday's wilt
    _persist();
    notifyListeners();
    return gain;
  }

  /// Call when a completed task is reopened (undone). Revokes the XP its
  /// completion granted — the exact last gain when it was this task's,
  /// otherwise the base amount — breaks the combo chain and walks back
  /// today's completion count. Total XP floors at zero: levels can drop,
  /// never below nothing. Returns the XP revoked.
  int revokeTaskCompletion(
      {int baseXp = BloomEngine.baseTaskXp, String? taskId}) {
    var revoke = baseXp;
    if (taskId != null &&
        taskId == _lastGainTaskId &&
        _lastGain != null &&
        _lastGain! > 0) {
      revoke = _lastGain!;
    }
    _lastGainTaskId = null;
    _lastGain = null;
    _totalXp = (_totalXp - revoke).clamp(0, 1 << 62);
    // An undo breaks the chain: the next completion restarts at x1.
    _comboCount = 0;
    _comboExpiresAt = null;
    _comboTimer?.cancel();
    final day = _dayKey(DateTime.now());
    if (_doneDayIso == day && _doneCount > 0) {
      _doneCount--;
    }
    _persist();
    notifyListeners();
    return revoke;
  }

  /// Daily ritual → variable token drop (70/25/5). Adds tokens, returns roll.
  MysteryReward claimDailyRitual() {
    final reward = BloomEngine.rollMysteryBloom(_random);
    _tokens += reward.tokens;
    _persist();
    notifyListeners();
    return reward;
  }

  /// Call once per app foreground (or after a recovery task). Handles
  /// same-day (no-op), next-day (+1), and broken streak (reset to 1).
  ///
  /// Milestones feel like milestones: 7/30/100-day streaks fire the
  /// celebration fanfare (heavy impact); an ordinary next-day tick fires
  /// the confirm tick. Same-day no-ops and broken resets stay silent —
  /// haptics reward progress, never punish a miss. Pass [quiet] at boot:
  /// browsers block vibration before the first user gesture and log an
  /// intervention, so the startup tick stays silent.
  void markDailyActive([DateTime? now, bool quiet = false]) {
    final day = _dayKey(now ?? DateTime.now());
    if (_lastDayIso == day) return;
    var grown = false;
    if (_lastDayIso == null) {
      _streak = 1;
      grown = true;
    } else {
      final last = DateTime.tryParse(_lastDayIso!);
      if (last == null) {
        _streak = 1;
        grown = true;
      } else {
        final gap = _dateOnly(DateTime.parse(day))
            .difference(_dateOnly(last))
            .inDays;
        if (gap == 1) {
          _streak += 1;
          grown = true;
        } else {
          _streak = 1;
        }
      }
    }
    _lastDayIso = day;
    _persist();
    notifyListeners();
    onStreakChanged?.call();
    if (!grown || quiet) return;
    if (_streak == 7 || _streak == 30 || _streak == 100) {
      AppHaptics.celebrate();
    } else {
      AppHaptics.confirm();
    }
  }

  void setStreak(int value) {
    _streak = value < 0 ? 0 : value;
    _persist();
    notifyListeners();
    onStreakChanged?.call();
  }

  void addTokens(int amount) {
    _tokens += amount;
    _persist();
    notifyListeners();
  }

  bool spendTokens(int amount) {
    if (_tokens < amount) return false;
    _tokens -= amount;
    _persist();
    notifyListeners();
    return true;
  }

  void addXp(int amount) {
    _totalXp += amount;
    _persist();
    notifyListeners();
  }

  /// Stake today's plan: up to 3 task ids each risking
  /// [BloomEngine.stakePerTask] XP overnight. Latest plan wins.
  /// Always previewed in the planner card — never a surprise.
  void stakeDay(List<String> taskIds, [DateTime? now]) {
    _stakedDayIso = _dayKey(now ?? DateTime.now());
    _stakedIds = taskIds.where((id) => id.isNotEmpty).take(3).toList();
    _persist();
    notifyListeners();
  }

  /// Settle a past day's stake. [doneIds] are finished task ids,
  /// [existingIds] are ids that still exist (deleted tasks are exempt —
  /// removing a task is planning, not failing).
  ///
  /// Returns a record: XP lost, tasks kept, tasks wilted, and whether the
  /// morning was forgiven. Loss is capped at
  /// [BloomEngine.maxDailyStakeLoss] and floored at the current level's
  /// base, so a bad morning costs progress but never a level. After two
  /// consecutive wilt mornings the next settle is forgiven (rest mode)
  /// and the streak mercy-resets.
  ({int lost, int kept, int wiltedCount, bool rested}) settleDay(
    Set<String> doneIds,
    Set<String> existingIds, [
    DateTime? now,
  ]) {
    final staked = _stakedIds;
    _stakedDayIso = null;
    _stakedIds = const [];
    if (staked.isEmpty) {
      _lastStakeLoss = 0;
      _persist();
      notifyListeners();
      return (lost: 0, kept: 0, wiltedCount: 0, rested: false);
    }
    var kept = 0;
    var missed = 0;
    for (final id in staked) {
      if (!existingIds.contains(id)) continue; // deleted: exempt
      if (doneIds.contains(id)) {
        kept++;
      } else {
        missed++;
      }
    }
    final loss = BloomEngine.stakeLossFor(missed);
    if (loss <= 0) {
      // Clean sweep (or all-exempt): the streak resets, no wilt.
      _wiltStreak = 0;
      _lastStakeLoss = 0;
      _persist();
      notifyListeners();
      return (lost: 0, kept: kept, wiltedCount: 0, rested: false);
    }
    if (_wiltStreak >= 2) {
      // Third tired morning: forgiven, streak mercy-resets, no wilt.
      _wiltStreak = 0;
      _wilted = false;
      _lastStakeLoss = 0;
      _persist();
      notifyListeners();
      return (lost: 0, kept: kept, wiltedCount: missed, rested: true);
    }
    // Floor at the current level's base — wilt, never de-level.
    final floor = BloomEngine.totalXpForLevel(level);
    _totalXp = (_totalXp - loss).clamp(floor, 1 << 62);
    _wilted = true;
    _wiltStreak++;
    _lastStakeLoss = loss;
    _persist();
    notifyListeners();
    return (lost: loss, kept: kept, wiltedCount: missed, rested: false);
  }

  /// Demo helper: max the profile to Full Bloom so the whole app can be
  /// seen at Lv 100 (Sakura, 5/5 season, live x5 combo, petals on).
  /// No server writes — local game juice only.
  void debugFullBloom() {
    _totalXp = BloomEngine.totalXpForLevel(BloomEngine.maxLevel);
    _tokens += 2500;
    if (_streak < 12) _streak = 12;
    final now = DateTime.now();
    _comboCount = 5;
    _lastCompletionAt = now;
    _comboExpiresAt = now.add(BloomEngine.comboWindow);
    _scheduleComboExpiry();
    _lastDayIso = _dayKey(now);
    _persist();
    notifyListeners();
  }

  /// Fresh slate for a new account (logout / switch / signup).
  /// Same shape as a first install: [load] would zero these anyway once
  /// the keys are gone, but memory needs the explicit clear or the new
  /// account inherits the old account's XP, streak and stakes.
  void resetForNewAccount() {
    _comboTimer?.cancel();
    _totalXp = 0;
    _tokens = 0;
    _streak = 0;
    _comboCount = 0;
    _lastCompletionAt = null;
    _comboExpiresAt = null;
    _lastDayIso = null;
    _stakedDayIso = null;
    _stakedIds = const [];
    _wilted = false;
    _lastStakeLoss = 0;
    _wiltStreak = 0;
    _doneDayIso = null;
    _doneCount = 0;
    _nudgedDayIso = null;
    _lastGainTaskId = null;
    _lastGain = null;
    _persist();
    notifyListeners();
  }

  /// Demo helper: back to a fresh Seedling.
  void debugReset() {
    _comboTimer?.cancel();
    _totalXp = 0;
    _tokens = 0;
    _streak = 1;
    _comboCount = 0;
    _lastCompletionAt = null;
    _comboExpiresAt = null;
    _lastDayIso = _dayKey(DateTime.now());
    _stakedDayIso = null;
    _stakedIds = const [];
    _wilted = false;
    _lastStakeLoss = 0;
    _wiltStreak = 0;
    _doneDayIso = _dayKey(DateTime.now());
    _doneCount = 0;
    _nudgedDayIso = null;
    _lastGainTaskId = null;
    _lastGain = null;
    _persist();
    notifyListeners();
  }

  // --- Persistence (best-effort, never throws into UI) ---

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _totalXp = prefs.getInt(_kXp) ?? 0;
      _tokens = prefs.getInt(_kTokens) ?? 0;
      _streak = prefs.getInt(_kStreak) ?? 0;
      _lastDayIso = prefs.getString(_kLastDay);
      _stakedDayIso = prefs.getString(_kStakeDay);
      _stakedIds = prefs.getStringList(_kStakeIds) ?? const [];
      _wilted = prefs.getBool(_kWilted) ?? false;
      _lastStakeLoss = prefs.getInt(_kLastStakeLoss) ?? 0;
      _wiltStreak = prefs.getInt(_kWiltStreak) ?? 0;
      _doneDayIso = prefs.getString(_kDoneDay);
      _doneCount = prefs.getInt(_kDoneCount) ?? 0;
      _nudgedDayIso = prefs.getString(_kNudgedDay);
      notifyListeners();
    } catch (_) {
      // Offline / first run: keep zeros.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kXp, _totalXp);
      await prefs.setInt(_kTokens, _tokens);
      await prefs.setInt(_kStreak, _streak);
      if (_lastDayIso != null) await prefs.setString(_kLastDay, _lastDayIso!);
      if (_stakedDayIso != null) {
        await prefs.setString(_kStakeDay, _stakedDayIso!);
      } else {
        await prefs.remove(_kStakeDay);
      }
      await prefs.setStringList(_kStakeIds, _stakedIds);
      await prefs.setBool(_kWilted, _wilted);
      await prefs.setInt(_kLastStakeLoss, _lastStakeLoss);
      await prefs.setInt(_kWiltStreak, _wiltStreak);
      if (_doneDayIso != null) {
        await prefs.setString(_kDoneDay, _doneDayIso!);
      }
      await prefs.setInt(_kDoneCount, _doneCount);
      if (_nudgedDayIso != null) {
        await prefs.setString(_kNudgedDay, _nudgedDayIso!);
      }
    } catch (_) {
      // Persistence is a bonus — gameplay continues in memory.
    }
  }

  void _scheduleComboExpiry() {
    _comboTimer?.cancel();
    final exp = _comboExpiresAt;
    if (exp == null) return;
    final wait = exp.difference(DateTime.now());
    if (wait.isNegative) {
      _comboCount = 0;
      return;
    }
    // Cap the OS timer at 15 min — exact, one shot, cheap.
    _comboTimer = Timer(wait, () {
      _comboCount = 0;
      _comboExpiresAt = null;
      notifyListeners();
    });
  }

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _comboTimer?.cancel();
    super.dispose();
  }
}
