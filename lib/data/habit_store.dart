import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'analytics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../game/gamification_state.dart';

/// A long-term aspiration habits attach to.
///
/// This is the "write your goals" layer the Habits tab was missing:
/// a goal is a named intention ("Run a 10k", "Calm mornings") that
/// groups daily habits and gives the streak a *reason*.
class HabitGoal {
  final String id;
  final String name;
  final String intention;
  final int iconIndex;
  final int accentIndex;

  const HabitGoal({
    required this.id,
    required this.name,
    this.intention = '',
    this.iconIndex = 0,
    this.accentIndex = 0,
  });

  HabitGoal copyWith({
    String? name,
    String? intention,
    int? iconIndex,
    int? accentIndex,
  }) =>
      HabitGoal(
        id: id,
        name: name ?? this.name,
        intention: intention ?? this.intention,
        iconIndex: iconIndex ?? this.iconIndex,
        accentIndex: accentIndex ?? this.accentIndex,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'intention': intention,
        'icon': iconIndex,
        'accent': accentIndex,
      };

  factory HabitGoal.fromJson(Map<String, dynamic> j) => HabitGoal(
        id: '${j['id']}',
        name: '${j['name'] ?? 'Goal'}',
        intention: '${j['intention'] ?? ''}',
        iconIndex: (j['icon'] as num?)?.toInt() ?? 0,
        accentIndex: (j['accent'] as num?)?.toInt() ?? 0,
      );
}

/// Daily check-in state for one habit on one day.
enum DayMark { done, partial, rest, none }
/// A single habit: yes/no ritual or counted practice with a target.
class Habit {
  final String id;
  final String name;
  final String intention;
  final bool counted;
  final num target;
  final String unit;
  final String? goalId;
  final int iconIndex;
  final int accentIndex;
  final bool paused;
  final Map<String, num> log;
  /// Streak freeze: while true the streak is shielded at [frozenStreak],
  /// stamped at freeze time. Skipped days don't decay it; logging keeps
  /// working. Unfreezing recomputes from the log (the shield only lasts
  /// while frozen). Matches the card copy: freeze is free, thaw is 500.
  final bool frozen;
  final int frozenStreak;
  const Habit({
    required this.id,
    required this.name,
    this.intention = '',
    this.counted = false,
    this.target = 1,
    this.unit = '',
    this.goalId,
    this.iconIndex = 0,
    this.accentIndex = 0,
    this.paused = false,
    Map<String, num>? log,
    this.frozen = false,
    this.frozenStreak = 0,
  }) : log = log ?? const {};
  Habit copyWith({
    String? name,
    String? intention,
    bool? counted,
    num? target,
    String? unit,
    String? Function()? goalId,
    int? iconIndex,
    int? accentIndex,
    bool? paused,
    Map<String, num>? log,
    bool? frozen,
    int? frozenStreak,
  }) =>
      Habit(
        id: id,
        name: name ?? this.name,
        intention: intention ?? this.intention,
        counted: counted ?? this.counted,
        target: target ?? this.target,
        unit: unit ?? this.unit,
        goalId: goalId != null ? goalId() : this.goalId,
        iconIndex: iconIndex ?? this.iconIndex,
        accentIndex: accentIndex ?? this.accentIndex,
        paused: paused ?? this.paused,
        log: log ?? this.log,
        frozen: frozen ?? this.frozen,
        frozenStreak: frozenStreak ?? this.frozenStreak,
      );
  num amountOn(String k) => log[k] ?? 0;
  bool doneOn(String k) {
    final v = amountOn(k);
    if (!counted) return v >= 1;
    final t = target <= 0 ? 1 : target;
    return v >= t;
  }
  bool get doneToday => doneOn(HabitStore.dayKey(DateTime.now()));
  int get streak => frozen
      ? frozenStreak
      : HabitStore.streakOf(log, counted, target);
  int get best {
    var bestRun = 0;
    var run = 0;
    final days = log.keys.toList()..sort();
    String? prev;
    for (final d in days) {
      if (!doneOn(d)) {
        run = 0;
        prev = null;
        continue;
      }
      if (prev != null && HabitStore.gapDays(prev, d) == 1) {
        run += 1;
      } else {
        run = 1;
      }
      if (run > bestRun) bestRun = run;
      prev = d;
    }
    return bestRun;
  }
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'intention': intention,
        'counted': counted,
        'target': target,
        'unit': unit,
        'goalId': goalId,
        'icon': iconIndex,
        'accent': accentIndex,
        'paused': paused,
        'frozen': frozen,
        'frozenStreak': frozenStreak,
        'log': log,
      };
  factory Habit.fromJson(Map<String, dynamic> j) {
    final rawLog = <String, num>{};
    final l = j['log'];
    if (l is Map) {
      l.forEach((k, v) {
        if (v is num) rawLog['$k'] = v;
      });
    }
    return Habit(
      id: '${j['id']}',
      name: '${j['name'] ?? 'Habit'}',
      intention: '${j['intention'] ?? ''}',
      counted: j['counted'] == true,
      target: (j['target'] as num?) ?? 1,
      unit: '${j['unit'] ?? ''}',
      goalId: j['goalId'] == null ? null : '${j['goalId']}',
      iconIndex: (j['icon'] as num?)?.toInt() ?? 0,
      accentIndex: (j['accent'] as num?)?.toInt() ?? 0,
      paused: j['paused'] == true,
      frozen: j['frozen'] == true,
      frozenStreak: (j['frozenStreak'] as num?)?.toInt() ?? 0,
      log: rawLog,
    );
  }
}
/// Store: habits + goals with local persistence.
class HabitStore extends ChangeNotifier {
  static const storageKey = 'bloom_habits_v1';
  static const historyDays = 60;
  static final HabitStore instance = HabitStore._();
  HabitStore._();
  List<HabitGoal> _goals = [];
  List<Habit> _habits = [];
  bool _loaded = false;
  List<HabitGoal> get goals => List.unmodifiable(_goals);
  List<Habit> get habits => List.unmodifiable(_habits);
  bool get loaded => _loaded;
  List<Habit> habitsFor(String? goalId) =>
      _habits.where((h) => h.goalId == goalId).toList();
  List<Habit> get ungrouped => habitsFor(null);
  HabitGoal? goalById(String? id) {
    if (id == null) return null;
    for (final g in _goals) {
      if (g.id == id) return g;
    }
    return null;
  }
  Habit? habitById(String id) {
    for (final h in _habits) {
      if (h.id == id) return h;
    }
    return null;
  }
  int get bestStreak {
    var best = 0;
    for (final h in _habits) {
      if (h.paused) continue;
      if (h.best > best) best = h.best;
    }
    return best;
  }
  int get doneTodayCount =>
      _habits.where((h) => !h.paused && h.doneToday).length;
  int get activeTodayCount => _habits.where((h) => !h.paused).length;
  double get todayProgress {
    final total = activeTodayCount;
    if (total == 0) return 0;
    return (doneTodayCount / total).clamp(0.0, 1.0);
  }
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  static int gapDays(String a, String b) {
    try {
      final pa = DateTime.parse(a);
      final pb = DateTime.parse(b);
      return dateOnly(pb).difference(dateOnly(pa)).inDays;
    } catch (_) {
      return 999;
    }
  }
  static bool doneOnLog(Map<String, num> log, String day, bool c, num t) {
    final v = log[day] ?? 0;
    if (!c) return v >= 1;
    return v >= (t <= 0 ? 1 : t);
  }
  static int streakOf(Map<String, num> log, bool counted, num target,
      [DateTime? now]) {
    final today = dateOnly(now ?? DateTime.now());
    var cursor = today;
    if (!doneOnLog(log, dayKey(cursor), counted, target)) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!doneOnLog(log, dayKey(cursor), counted, target)) return 0;
    }
    var run = 0;
    while (doneOnLog(log, dayKey(cursor), counted, target)) {
      run += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return run;
  }

  /// Habits whose streak dies tonight: streak alive, not done today,
  /// not paused. Longest streak first, max 3 — one quiet nudge, not a list.
  static List<Habit> atRisk(Iterable<Habit> habits, [DateTime? now]) {
    final n = now ?? DateTime.now();
    final today = dayKey(n);
    final out = habits
        .where((h) => !h.paused && h.streak > 0 && !h.doneOn(today))
        .toList()
      ..sort((a, b) => b.streak.compareTo(a.streak));
    return out.take(3).toList();
  }
  static int _idSeq = 0;
  // Monotonic suffix: two rows created in the same microsecond (preset
  // apply, fast test clocks) must never share an id — keys collide.
  String _newId(String p) =>
      '$p${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

/// RitualPreset + PresetHabit live at the bottom of this file, after
/// [HabitStore] (Dart forbids nested class declarations).
  Future<HabitGoal> addGoal({required String name, String intention = '', int iconIndex = 0, int accentIndex = 0}) async {
    final g = HabitGoal(id: _newId('g'), name: name.trim().isEmpty ? 'Untitled goal' : name.trim(), intention: intention.trim(), iconIndex: iconIndex, accentIndex: accentIndex);
    _goals = [..._goals, g];
    notifyListeners();
    await persist();
    return g;
  }
  Future<void> updateGoal(String id, {String? name, String? intention, int? iconIndex, int? accentIndex}) async {
    _goals = [for (final g in _goals) if (g.id == id) g.copyWith(name: name?.trim().isEmpty ?? true ? null : name?.trim(), intention: intention?.trim(), iconIndex: iconIndex, accentIndex: accentIndex) else g];
    notifyListeners();
    await persist();
  }
  Future<void> removeGoal(String id) async {
    var found = false;
    final keptG = <HabitGoal>[];
    for (final g in _goals) {
      if (g.id == id) { found = true; } else { keptG.add(g); }
    }
    if (!found) return;
    _goals = keptG;
    _habits = [for (final h in _habits) if (h.goalId == id) h.copyWith(goalId: () => null) else h];
    notifyListeners();
    await persist();
  }
  Future<Habit> addHabit({required String name, String intention = '', bool counted = false, num target = 1, String unit = '', String? goalId, int iconIndex = 0, int accentIndex = 0}) async {
    final h = Habit(id: _newId('h'), name: name.trim().isEmpty ? 'Untitled habit' : name.trim(), intention: intention.trim(), counted: counted, target: counted ? (target <= 0 ? 1 : target) : 1, unit: unit.trim(), goalId: goalId, iconIndex: iconIndex, accentIndex: accentIndex);
    _habits = [..._habits, h];
    notifyListeners();
    await persist();
    return h;
  }
  Future<void> updateHabit(String id, {String? name, String? intention, bool? counted, num? target, String? unit, String? Function()? goalId, int? iconIndex, int? accentIndex, bool? paused}) async {
    _habits = [for (final h in _habits) if (h.id == id) h.copyWith(name: name?.trim().isEmpty ?? true ? null : name?.trim(), intention: intention?.trim(), counted: counted, target: target, unit: unit?.trim(), goalId: goalId, iconIndex: iconIndex, accentIndex: accentIndex, paused: paused) else h];
    notifyListeners();
    await persist();
  }
  Future<bool> toggleToday(String id, [DateTime? now]) async {
    final day = dayKey(now ?? DateTime.now());
    var result = false;
    _habits = [for (final h in _habits) if (h.id == id && !h.counted) (() { final next = {...h.log}; if ((next[day] ?? 0) >= 1) { next.remove(day); result = false; } else { next[day] = 1; result = true; } return h.copyWith(log: trim(next)); })() else h];
    notifyListeners();
    await persist();
    if (result) BloomAnalytics.habitCheckin();
    return result;
  }
  Future<num> logToday(String id, num delta, [DateTime? now]) async {
    final day = dayKey(now ?? DateTime.now());
    num result = 0;
    _habits = [for (final h in _habits) if (h.id == id && h.counted) (() { final next = {...h.log}; final v = (next[day] ?? 0) + delta; if (v <= 0) { next.remove(day); result = 0; } else { next[day] = v; result = v; } return h.copyWith(log: trim(next)); })() else h];
    notifyListeners();
    await persist();
    return result;
  }
  Future<Habit?> removeHabit(String id) async {
    Habit? removed;
    final kept = <Habit>[];
    for (final h in _habits) {
      if (h.id == id) { removed = h; } else { kept.add(h); }
    }
    if (removed == null) return null;
    _habits = kept;
    notifyListeners();
    await persist();
    return removed;
  }
  /// Thaw price, matching the card copy ("Unfreeze for 500").
  static const int unfreezeTokens = 500;
  /// Freeze is free: stamp the current streak as the shield. Logging
  /// keeps working underneath; the shield holds until thaw.
  Future<bool> freezeHabit(String id) async {
    final h = habitById(id);
    if (h == null || h.frozen) return false;
    _habits = [for (final x in _habits) if (x.id == id) x.copyWith(frozen: true, frozenStreak: HabitStore.streakOf(x.log, x.counted, x.target)) else x];
    notifyListeners();
    await persist();
    return true;
  }
  /// Thaw costs [unfreezeTokens]; spent through the central balance so
  /// the server-validated economy stays the single source of truth.
  /// Returns false (no state touched) when the balance is short.
  Future<bool> unfreezeHabit(String id) async {
    final h = habitById(id);
    if (h == null || !h.frozen) return false;
    final paid = GamificationStateNotifier.instance.spendTokens(unfreezeTokens);
    if (!paid) return false;
    _habits = [for (final x in _habits) if (x.id == id) x.copyWith(frozen: false, frozenStreak: 0) else x];
    notifyListeners();
    await persist();
    return true;
  }
  Future<void> restoreHabit(Habit h) async {
    if (habitById(h.id) != null) return;
    _habits = [..._habits, h];
    notifyListeners();
    await persist();
  }
  @visibleForTesting
  void debugFill({List<HabitGoal>? goals, List<Habit>? habits}) {
    _goals = goals ?? [];
    _habits = habits ?? [];
    _loaded = true;
    notifyListeners();
  }
  Map<String, num> trim(Map<String, num> log) {
    if (log.length <= HabitStore.historyDays) return log;
    final keys = log.keys.toList()..sort();
    final drop = log.length - HabitStore.historyDays;
    final next = {...log};
    for (var i = 0; i < drop; i++) {
      next.remove(keys[i]);
    }
    return next;
  }
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        // Trust rule: a fresh account starts honestly empty — the
        // guided empty state ("Write your first goal") teaches the
        // shape. Seeded demo streaks were someone else's life.
        _goals = [];
        _habits = [];
        _loaded = true;
        notifyListeners();
        return;
      }
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final gs = j['goals'];
      final hs = j['habits'];
      _goals = gs is List ? gs.whereType<Map>().map((e) => HabitGoal.fromJson(Map<String, dynamic>.from(e))).toList() : [];
      _habits = hs is List ? hs.whereType<Map>().map((e) => Habit.fromJson(Map<String, dynamic>.from(e))).toList() : [];
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // A corrupt cache is not an excuse to conjure data: empty.
      _goals = [];
      _habits = [];
      _loaded = true;
      notifyListeners();
    }
  }
  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode({'goals': [for (final g in _goals) g.toJson()], 'habits': [for (final h in _habits) h.toJson()]}));
    } catch (_) {}
  }
}

/// One-tap starter ritual: a goal with its tiny habits, applied from
/// the empty state ("or start from a ritual").
class RitualPreset {
  final String id;
  final String goalName;
  final String goalIntention;
  final int goalIcon;
  final int goalAccent;
  final List<PresetHabit> habits;

  const RitualPreset({
    required this.id,
    required this.goalName,
    this.goalIntention = '',
    this.goalIcon = 0,
    this.goalAccent = 0,
    this.habits = const [],
  });
}

class PresetHabit {
  final String name;
  final String intention;
  final bool counted;
  final num target;
  final String unit;
  final int iconIndex;

  const PresetHabit(
    this.name, {
    this.intention = '',
    this.counted = false,
    this.target = 1,
    this.unit = '',
    this.iconIndex = 0,
  });
}

extension RitualPresets on HabitStore {
  /// The starter shelf. Small on purpose: a goal plus two tiny habits.
  /// Icons index into the sheet's `_habitIcons` (sprout, dumbbell,
  /// droplets, footprints, brain, book, moon, flower).
  static const presets = [
    RitualPreset(
      id: 'calm-mornings',
      goalName: 'Calm mornings',
      goalIntention: 'Start the day steady instead of reactive.',
      habits: [
        PresetHabit('Morning meditation',
            intention: '10 quiet minutes before screens.', iconIndex: 4),
        PresetHabit('Drink water',
            intention: 'Stay hydrated through deep-work blocks.',
            counted: true, target: 8, unit: 'glasses', iconIndex: 2),
      ],
    ),
    RitualPreset(
      id: 'deep-work',
      goalName: 'Deep work',
      goalIntention: 'Protect attention for what matters.',
      goalIcon: 4,
      goalAccent: 2,
      habits: [
        PresetHabit('Single-task sprint',
            intention: 'One 25-minute block, phone away.', iconIndex: 6),
        PresetHabit('Evening shutdown',
            intention: 'Close loops so tomorrow starts clean.',
            iconIndex: 7),
      ],
    ),
    RitualPreset(
      id: 'strong-body',
      goalName: 'Strong body',
      goalIntention: 'Move daily so energy compounds.',
      goalIcon: 1,
      goalAccent: 1,
      habits: [
        PresetHabit('Evening walk',
            intention: 'Unwind and clear the head.', iconIndex: 3),
        PresetHabit('Drink water',
            intention: 'Stay hydrated through deep-work blocks.',
            counted: true, target: 8, unit: 'glasses', iconIndex: 2),
      ],
    ),
  ];

  static String _norm(String s) => s.trim().toLowerCase();

  /// Plant a preset. Names are the identity: the goal is reused when
  /// one already shares its name, and habits with a matching name
  /// under it are skipped. Returns how many rows were actually added,
  /// so the UI can say "planted" vs "already growing".
  Future<int> applyPreset(RitualPreset preset) async {
    var added = 0;
    var goal = goals.where((g) => _norm(g.name) == _norm(preset.goalName));
    final HabitGoal g;
    if (goal.isEmpty) {
      g = await addGoal(
        name: preset.goalName,
        intention: preset.goalIntention,
        iconIndex: preset.goalIcon,
        accentIndex: preset.goalAccent,
      );
      added++;
    } else {
      g = goal.first;
    }
    final have = habitsFor(g.id).map((h) => _norm(h.name)).toSet();
    for (final p in preset.habits) {
      if (have.contains(_norm(p.name))) continue;
      await addHabit(
        name: p.name,
        intention: p.intention,
        counted: p.counted,
        target: p.target,
        unit: p.unit,
        goalId: g.id,
        iconIndex: p.iconIndex,
      );
      added++;
    }
    return added;
  }
}
