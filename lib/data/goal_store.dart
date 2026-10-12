import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One milestone step inside a long-term project goal.
class GoalMilestone {
  final String id;
  final String title;
  final bool done;

  const GoalMilestone({
    required this.id,
    required this.title,
    this.done = false,
  });

  GoalMilestone copyWith({String? title, bool? done}) => GoalMilestone(
        id: id,
        title: title ?? this.title,
        done: done ?? this.done,
      );

  factory GoalMilestone.fromJson(Map<String, dynamic> j) => GoalMilestone(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        done: j['done'] is bool
            ? j['done'] as bool
            : '${j['done']}'.toLowerCase() == 'true',
      );

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'done': done};
}

/// A long-term project goal: title, target date, and a milestone
/// checklist. Progress derives from checked steps — no manual %.
class ProjectGoal {
  final String id;
  final String title;
  final DateTime? targetDate;
  final List<GoalMilestone> milestones;
  final DateTime createdAt;

  const ProjectGoal({
    required this.id,
    required this.title,
    this.targetDate,
    this.milestones = const [],
    required this.createdAt,
  });

  /// 0..1 across milestone steps. Stepless goals read 0 until done
  /// elsewhere — the UI hides the bar when there is nothing to average.
  double get progress {
    if (milestones.isEmpty) return 0;
    final done = milestones.where((m) => m.done).length;
    return done / milestones.length;
  }

  int get doneCount => milestones.where((m) => m.done).length;

  /// Whole days until the target date (negative = overdue). Null when
  /// the goal has no date.
  int? daysRemaining([DateTime? now]) {
    final target = targetDate;
    if (target == null) return null;
    final n = now ?? DateTime.now();
    return DateTime(target.year, target.month, target.day)
        .difference(DateTime(n.year, n.month, n.day))
        .inDays;
  }

  ProjectGoal copyWith({
    String? title,
    DateTime? Function()? targetDate,
    List<GoalMilestone>? milestones,
  }) =>
      ProjectGoal(
        id: id,
        title: title ?? this.title,
        targetDate: targetDate != null ? targetDate() : this.targetDate,
        milestones: milestones ?? this.milestones,
        createdAt: createdAt,
      );

  factory ProjectGoal.fromJson(Map<String, dynamic> j) => ProjectGoal(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        targetDate: j['target_date'] == null
            ? null
            : DateTime.tryParse('${j['target_date']}'),
        milestones: j['milestones'] is List
            ? (j['milestones'] as List)
                .whereType<Map<String, dynamic>>()
                .map(GoalMilestone.fromJson)
                .toList()
            : const [],
        createdAt:
            DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'target_date': targetDate?.toIso8601String(),
        'milestones': [for (final m in milestones) m.toJson()],
        'created_at': createdAt.toIso8601String(),
      };
}

/// Local-first project goals: persisted to SharedPreferences, fully
/// offline. No server column, no sync daemon — long-term plans belong
/// to the device until the backend grows a goals table.
class GoalStore extends ChangeNotifier {
  static const storageKey = 'bloom_project_goals_v1';

  static final GoalStore instance = GoalStore._();
  GoalStore._();

  List<ProjectGoal> _goals = [];
  bool _loaded = false;

  List<ProjectGoal> get goals => List.unmodifiable(_goals);
  bool get loaded => _loaded;

  static int _idSeq = 0;
  String _newId(String p) =>
      '$p${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  Future<ProjectGoal> addGoal({
    required String title,
    DateTime? targetDate,
    List<String> steps = const [],
  }) async {
    final clean = steps
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(10)
        .toList();
    final goal = ProjectGoal(
      id: _newId('g'),
      title: title.trim().isEmpty ? 'Untitled goal' : title.trim(),
      targetDate: targetDate,
      milestones: [
        for (final s in clean)
          GoalMilestone(id: _newId('m'), title: s),
      ],
      createdAt: DateTime.now(),
    );
    _goals = [..._goals, goal];
    notifyListeners();
    await persist();
    return goal;
  }

  Future<void> toggleMilestone(String goalId, String milestoneId) async {
    final i = _goals.indexWhere((g) => g.id == goalId);
    if (i == -1) return;
    final goal = _goals[i];
    final j = goal.milestones.indexWhere((m) => m.id == milestoneId);
    if (j == -1) return;
    final steps = [...goal.milestones];
    steps[j] = steps[j].copyWith(done: !steps[j].done);
    _goals = [..._goals]..[i] = goal.copyWith(milestones: steps);
    notifyListeners();
    await persist();
  }

  Future<void> removeGoal(String goalId) async {
    if (!_goals.any((g) => g.id == goalId)) return;
    _goals = _goals.where((g) => g.id != goalId).toList();
    notifyListeners();
    await persist();
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) {
        _loaded = true;
        notifyListeners();
        return;
      }
      final j = jsonDecode(raw);
      final list = j is Map && j['goals'] is List
          ? (j['goals'] as List).whereType<Map<String, dynamic>>()
          : const <Map<String, dynamic>>[];
      final parsed = <ProjectGoal>[];
      for (final g in list) {
        try {
          parsed.add(ProjectGoal.fromJson(g));
        } catch (_) {
          // Skip corrupt entries, keep the rest.
        }
      }
      _goals = parsed;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          storageKey, jsonEncode({'goals': [for (final g in _goals) g.toJson()]}));
    } catch (_) {}
  }

  /// Fresh slate for a new account. [load] keeps stale memory when the
  /// key is missing, so the wipe needs this explicit clear.
  Future<void> resetForNewAccount() async {
    _goals = [];
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}
    notifyListeners();
  }

  @visibleForTesting
  void debugFill([List<ProjectGoal>? goals]) {
    _goals = List.of(goals ?? const []);
    _loaded = true;
    notifyListeners();
  }
}
