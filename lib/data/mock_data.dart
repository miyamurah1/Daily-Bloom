import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../theme/sakura_theme.dart';

/// Simple model shared by mock + Postgres backend.
/// status mirrors the DB check: todo | in_progress | done.
class Task {
  final String id;
  final String title;
  final String tag;
  final String folder;
  final String description;
  final String priority;
  final String recurring;
  final int position;
  final int comments;
  final String avatarLabel;
  final String status;
  final DateTime? dueAt;
  final List<Subtask>? subtasks;
  final int? focusMinutes;
  final DateTime? createdAt;
  final DateTime? completedAt;

  /// Commitment cadence: 'once' (a task) or 'daily' (a habit). The
  /// unifying seam between the two formerly separate models — a habit
  /// is just a commitment you tend every day.
  final String cadence;

  /// Habit-only fields (ignored when [cadence] == 'once'). Kept on
  /// [Task] so a single model carries both kinds.
  final bool habitCounted;
  final num habitTarget;
  final String habitUnit;
  final String? habitGoalId;
  final int habitIconIndex;
  final int habitAccentIndex;
  final bool habitPaused;
  final Map<String, num> habitLog;
  final bool habitFrozen;
  final int habitFrozenStreak;

  const Task({
    required this.id,
    required this.title,
    required this.tag,
    this.folder = 'Productivity',
    this.description = '',
    this.priority = 'none',
    this.recurring = 'none',
    this.position = 0,
    this.comments = 0,
    this.avatarLabel = '禅',
    this.status = 'todo',
    this.dueAt,
    this.subtasks,
    this.focusMinutes,
    this.createdAt,
    this.completedAt,
    this.cadence = 'once',
    this.habitCounted = false,
    this.habitTarget = 1,
    this.habitUnit = '',
    this.habitGoalId,
    this.habitIconIndex = 0,
    this.habitAccentIndex = 0,
    this.habitPaused = false,
    this.habitLog = const <String, num>{},
    this.habitFrozen = false,
    this.habitFrozenStreak = 0,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: '${j['id']}',
        title: '${j['title']}',
        tag: '${j['tag'] ?? 'General'}',
        folder: '${j['folder'] ?? 'Productivity'}',
        description: '${j['description'] ?? ''}',
        priority: '${j['priority'] ?? 'none'}',
        recurring: '${j['recurring'] ?? 'none'}',
        position: (j['position'] as num?)?.toInt() ?? 0,
        comments: (j['comments'] as num?)?.toInt() ?? 0,
        avatarLabel: '${j['avatar_label'] ?? '禅'}',
        status: '${j['status'] ?? 'todo'}',
        dueAt: j['due_at'] == null
            ? null
            : DateTime.tryParse('${j['due_at']}'),
        createdAt: j['created_at'] == null
            ? null
            : DateTime.tryParse('${j['created_at']}'),
        completedAt: j['completed_at'] == null
            ? null
            : DateTime.tryParse('${j['completed_at']}'),
        subtasks: j['subtasks'] is List
            ? (j['subtasks'] as List)
                .map((e) => Subtask.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
        focusMinutes: j['focus_minutes'] == null
            ? null
            : (j['focus_minutes'] as num).toInt(),
        cadence: '${j['cadence'] ?? 'once'}',
        habitCounted: j['habit_counted'] == true,
        habitTarget: (j['habit_target'] as num?) ?? 1,
        habitUnit: '${j['habit_unit'] ?? ''}',
        habitGoalId: j['habit_goal_id'] == null
            ? null
            : '${j['habit_goal_id']}',
        habitIconIndex: (j['habit_icon'] as num?)?.toInt() ?? 0,
        habitAccentIndex: (j['habit_accent'] as num?)?.toInt() ?? 0,
        habitPaused: j['habit_paused'] == true,
        habitLog: j['habit_log'] is Map
            ? Map<String, num>.from(j['habit_log'] as Map)
            : const {},
        habitFrozen: j['habit_frozen'] == true,
        habitFrozenStreak: (j['habit_frozen_streak'] as num?)?.toInt() ?? 0,
      );

  /// Backup serialization: mirrors [fromJson] keys so an export
  /// round-trips through [Task.fromJson] losslessly.
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tag': tag,
        'folder': folder,
        'description': description,
        'priority': priority,
        'recurring': recurring,
        'position': position,
        'comments': comments,
        'avatar_label': avatarLabel,
        'status': status,
        'due_at': dueAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'completed_at': completedAt?.toIso8601String(),
        'subtasks': subtasks
            ?.map((s) => {
                  'id': s.id,
                  'task_id': s.taskId,
                  'title': s.title,
                  'done': s.done,
                  'position': s.position,
                  'created_at': s.startedAt.toIso8601String(),
                  'completed_at': s.completedAt?.toIso8601String(),
                })
            .toList(),
        'focus_minutes': focusMinutes,
      };

  Task copyWith({
    String? title,
    String? tag,
    String? folder,
    String? description,
    String? priority,
    String? recurring,
    int? position,
    String? status,
    DateTime? dueAt,
    bool clearDue = false,
    List<Subtask>? subtasks,
    int? focusMinutes,
    DateTime? createdAt,
    DateTime? completedAt,
    String? cadence,
    bool? habitCounted,
    num? habitTarget,
    String? habitUnit,
    String? Function()? habitGoalId,
    int? habitIconIndex,
    int? habitAccentIndex,
    bool? habitPaused,
    Map<String, num>? habitLog,
    bool? habitFrozen,
    int? habitFrozenStreak,
  }) =>
      Task(
        id: id,
        title: title ?? this.title,
        tag: tag ?? this.tag,
        folder: folder ?? this.folder,
        description: description ?? this.description,
        priority: priority ?? this.priority,
        recurring: recurring ?? this.recurring,
        position: position ?? this.position,
        comments: comments,
        avatarLabel: avatarLabel,
        status: status ?? this.status,
        dueAt: clearDue ? null : (dueAt ?? this.dueAt),
        subtasks: subtasks ?? this.subtasks,
        focusMinutes: focusMinutes ?? this.focusMinutes,
        createdAt: createdAt ?? this.createdAt,
        completedAt: completedAt ?? this.completedAt,
        cadence: cadence ?? this.cadence,
        habitCounted: habitCounted ?? this.habitCounted,
        habitTarget: habitTarget ?? this.habitTarget,
        habitUnit: habitUnit ?? this.habitUnit,
        habitGoalId: habitGoalId != null ? habitGoalId() : this.habitGoalId,
        habitIconIndex: habitIconIndex ?? this.habitIconIndex,
        habitAccentIndex: habitAccentIndex ?? this.habitAccentIndex,
        habitPaused: habitPaused ?? this.habitPaused,
        habitLog: habitLog ?? this.habitLog,
        habitFrozen: habitFrozen ?? this.habitFrozen,
        habitFrozenStreak: habitFrozenStreak ?? this.habitFrozenStreak,
      );

  /// A habit is a daily commitment; a task is a one-off.
  bool get isHabit => cadence == 'daily';

  /// Whether the commitment is done for the given day key (habit only).
  bool doneOn(String dayKey) {
    if (cadence != 'daily') return status == 'done';
    final threshold = habitCounted ? habitTarget : 1;
    return (habitLog[dayKey] ?? 0) >= threshold;
  }
}

/// Kanban-correct loop: completing from anywhere lands in done;
/// reopening a done task returns it to the To-Do pile (never straight
/// into In Progress, which would silently break the WIP limit).
/// Single source so Home, Board, folders and detail never disagree
/// about where a tap sends a task.
String nextStatus(Task task) =>
    task.status == 'done' ? 'todo' : 'done';

/// Day boundary helper: start of the task's local day count.
DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// True when an open task's due date already passed.
bool isOverdue(Task task, [DateTime? now]) {
  final due = task.dueAt;
  if (due == null || task.status == 'done') return false;
  return due.isBefore(now ?? DateTime.now());
}

/// True when an open task is due today (any time today).
bool isDueToday(Task task, [DateTime? now]) {
  final due = task.dueAt;
  if (due == null || task.status == 'done' || isOverdue(task, now)) {
    return false;
  }
  final n = now ?? DateTime.now();
  return _dayOnly(due.toLocal()).isAtSameMomentAs(_dayOnly(n));
}

/// To-Do float: overdue first, due-today next, everything else untouched.
/// Stable — manual position order survives inside each band, so user
/// ordering is never scrambled, only banded.
List<Task> floatUrgent(List<Task> tasks, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final over = <Task>[];
  final today = <Task>[];
  final rest = <Task>[];
  for (final t in tasks) {
    if (isOverdue(t, n)) {
      over.add(t);
    } else if (isDueToday(t, n)) {
      today.add(t);
    } else {
      rest.add(t);
    }
  }
  return [...over, ...today, ...rest];
}

/// Elapsed wall-clock time for one task: created -> done (or now while
/// open). Null when the server never sent `created_at` (offline mocks).
Duration? taskElapsed(Task t, [DateTime? now]) {
  final start = t.createdAt;
  if (start == null) return null;
  // A due date is a deadline, not an end: an open task keeps counting
  // against the clock. (Using dueAt here clamped future deadlines to 0m.)
  final end = t.completedAt ?? now ?? DateTime.now();
  if (end.isBefore(start)) return Duration.zero;
  return end.difference(start);
}

/// Compact duration label: `45m`, `3h 12m`, `2d 4h`.
String fmtElapsed(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 48) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
  final days = d.inDays;
  final h = d.inHours % 24;
  return h == 0 ? '${days}d' : '${days}d ${h}h';
}

const todoTasks = <Task>[
  Task(
    id: 't1',
    title: 'Morning light — step outside for 10 minutes',
    tag: 'Ritual',
    comments: 2,
    avatarLabel: '朝',
    status: 'todo',
    description: 'No phone. Just light, air, and one slow breath.',
  ),
  Task(
    id: 't2',
    title: 'Clear one small corner — desk, inbox, or mind',
    tag: 'Care',
    comments: 5,
    avatarLabel: '静',
    status: 'todo',
    description: 'Pick the smallest mess you can see. Tidy only that.',
  ),
  Task(
    id: 't3',
    title: 'One 25-minute deep focus session',
    tag: 'Focus',
    comments: 1,
    avatarLabel: '集中',
    status: 'todo',
    description: 'Single task, timer on, everything else away.',
  ),
];

const inProgressTasks = <Task>[
  Task(
    id: 'p1',
    title: 'Evening shutdown — write tomorrow’s first step',
    tag: 'Ritual',
    comments: 3,
    avatarLabel: '桜',
    status: 'in_progress',
    description: 'End the day with one clear line for tomorrow.',
  ),
  Task(
    id: 'p2',
    title: 'Drink water, stretch, breathe — reset the body',
    tag: 'Care',
    comments: 0,
    avatarLabel: '和',
    status: 'in_progress',
    description: 'Two minutes. Shoulders down, jaw soft.',
  ),
];

const doneTasks = <Task>[
  Task(id: 'd1', title: 'Morning meditation + journal setup', tag: 'Ritual', comments: 0, status: 'done'),
  Task(id: 'd2', title: 'Plant your first intention for today', tag: 'Bloom', comments: 4, status: 'done'),
  Task(id: 'd3', title: 'Tidy one shelf and smile at it', tag: 'Care', comments: 1, status: 'done'),
  Task(id: 'd4', title: 'Evening shutdown checklist', tag: 'Ritual', comments: 0, status: 'done'),
];

/// First-run starter pack — 3 warm, completable tasks shown on a fresh,
/// live-but-empty account. Clearly a welcome gift, never fake history:
/// completing one runs the real loop (heatmap + XP + combo).
const starterTasks = <Task>[
  Task(
    id: 'starter-1',
    title: 'Say hello — complete this first bloom',
    tag: 'Welcome',
    comments: 0,
    avatarLabel: '🌸',
    status: 'todo',
    description: 'Tap this card done and watch your garden wake up.',
  ),
  Task(
    id: 'starter-2',
    title: 'Pin today’s intention above',
    tag: 'Welcome',
    comments: 0,
    avatarLabel: '☀',
    status: 'todo',
    description: 'One small focus for today. Edit the card above to set it.',
  ),
  Task(
    id: 'starter-3',
    title: 'Start one 25-minute focus session',
    tag: 'Welcome',
    comments: 0,
    avatarLabel: '◐',
    status: 'todo',
    description: 'Open any task → timer. Even 5 minutes counts.',
  ),
];

/// Mock 12-week x 7-day contribution levels (0-5, where 5 = gold peak).
/// Deterministic pseudo-random so UI looks organic but stable.
List<int> mockHeatmapData({int weeks = 12}) {
  final pattern = <int>[
    1, 2, 0, 3, 1, 4, 2,
    0, 1, 2, 2, 3, 1, 0,
    2, 3, 1, 4, 2, 1, 3,
    1, 0, 2, 5, 1, 2, 0,
  ];
  return List<int>.generate(weeks * 7, (i) => pattern[i % pattern.length]);
}

/// Heat colors follow the ACTIVE theme (store skins re-tint the grid).
Color heatColorFor(int level) {
  switch (level) {
    case 1:
      return SakuraColors.heat1;
    case 2:
      return SakuraColors.heat2;
    case 3:
      return SakuraColors.heat3;
    case 4:
      return SakuraColors.heat4;
    case 5:
      return SakuraColors.heatPeak;
    case 0:
    default:
      return SakuraColors.heat0;
  }
}
