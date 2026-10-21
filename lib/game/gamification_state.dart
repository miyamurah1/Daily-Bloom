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
  static const _kGraceMonth = 'bloom_game_grace_month';
  static const _kGraceUsed = 'bloom_game_grace_used';
  static const _kDoneDay = 'bloom_game_done_day';
  static const _kDoneCount = 'bloom_game_done_count';
  static const _kNudgedDay = 'bloom_game_nudged_day';

  /// Prefs keys from the removed stake/wilt system (v1.0). Never read;
  /// purged once on [load] so upgraded devices don't carry dead data.
  static const _legacyStakeKeys = <String>[
    'bloom_game_stake_day',
    'bloom_game_stake_ids',
    'bloom_game_wilted',
    'bloom_game_last_stake_loss',
    'bloom_game_wilt_streak',
  ];

  /// App-wide singleton — screens share one combo / XP / streak.
  static final GamificationStateNotifier instance =
      GamificationStateNotifier();

  int _totalXp = 0;
  int _tokens = 0;
  int _streak = 0;
  String? _lastDayIso;
  String? _graceMonth; // "YYYY-MM" of the month the grace day was used
  bool _graceUsed = false;

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

  GamificationStateNotifier({Random? random});

  // --- Reads (cheap getters, safe to call in build) ---

  int get totalXp => _totalXp;
  int get tokens => _tokens;
  int get streak => _streak;
  bool get graceDayAvailable {
    final month = _dayKey(DateTime.now()).substring(0, 7);
    if (_graceMonth != month) return true;
    return !_graceUsed;
  }

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

  /// Daily ritual \u2192 fixed meaningful reward. No loot box: rewards
  /// completing your focus, not volume. Adds tokens, returns roll.
  MysteryReward claimDailyRitual() {
    const reward = MysteryReward(25);
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
        } else if (gap == 2 && !_graceUsedThisMonth(day)) {
          // Grace Day: one missed day per month doesn't break the streak.
          _streak += 1;
          grown = true;
          _graceMonth = day.substring(0, 7);
          _graceUsed = true;
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
  /// account inherits the old account's XP and streak.
  void resetForNewAccount() {
    _comboTimer?.cancel();
    _totalXp = 0;
    _tokens = 0;
    _streak = 0;
    _comboCount = 0;
    _lastCompletionAt = null;
    _comboExpiresAt = null;
    _lastDayIso = null;
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
      _graceMonth = prefs.getString(_kGraceMonth);
      _graceUsed = prefs.getBool(_kGraceUsed) ?? false;
      _doneDayIso = prefs.getString(_kDoneDay);
      _doneCount = prefs.getInt(_kDoneCount) ?? 0;
      _nudgedDayIso = prefs.getString(_kNudgedDay);
      // One-time purge of the removed stake/wilt keys (v1.0 punishment
      // mechanics). Best-effort — a failing remove must not block boot.
      for (final key in _legacyStakeKeys) {
        try {
          await prefs.remove(key);
        } catch (_) {}
      }
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
      if (_graceMonth != null) await prefs.setString(_kGraceMonth, _graceMonth!);
      await prefs.setBool(_kGraceUsed, _graceUsed);
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

  bool _graceUsedThisMonth(String day) {
    final month = day.substring(0, 7);
    if (_graceMonth != month) return false;
    return _graceUsed;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _comboTimer?.cancel();
    super.dispose();
  }
}
