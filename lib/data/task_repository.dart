import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'analytics.dart';
import 'auth_store.dart';
import 'guest_store.dart';
import 'mock_data.dart';

/// Single source of truth for all tasks across the application.
///
/// Features:
/// - Reactive: any modification notifies all listening screens immediately.
/// - Optimistic UI: screen updates happen at 0ms latency; syncs with backend in background.
/// - Persistent Local Cache: persists real tasks to SharedPreferences so offline use
///   shows user data rather than static dummy fixtures.
class TaskRepository extends ChangeNotifier {
  static const _kTasksCache = 'bloom_tasks_cache_v2';
  static const _kOutbox = 'bloom_outbox_v1';
  static const _kDeadLetters = 'bloom_outbox_dead_v1';

  /// After this many failed replay attempts a mutation is parked in the
  /// dead-letter store instead of blocking the FIFO forever.
  static const _maxAttempts = 5;

  TaskRepository._();
  static final TaskRepository instance = TaskRepository._();

  /// Test seam: swap the API implementation to drive online/offline
  /// scenarios deterministically. Production leaves the default.
  @visibleForTesting
  static BloomApi Function() apiFactory = BloomApi.new;

  late final BloomApi _api = apiFactory();

  List<Task> _tasks = [];

  /// FIFO queue of mutations that could not reach the backend while
  /// offline (or during a dropout). Persisted to SharedPreferences and
  /// replayed in order the next time [loadRemote] succeeds.
  final List<Map<String, dynamic>> _outbox = [];

  /// Mutations that kept failing (validation / server errors) after
  /// [_maxAttempts]. Kept aside so they can never wedge the queue;
  /// inspectable via [deadLetterCount] and clearable via
  /// [discardDeadLetters].
  final List<Map<String, dynamic>> _deadLetters = [];
  bool _loading = false;
  String? _error;
  bool _isInitialized = false;

  /// Test seam: disable the background retry loop (widget tests must not
  /// leave pending timers).
  @visibleForTesting
  static bool autoRetry = true;

  /// How often to retry the outbox while offline. Short in tests.
  @visibleForTesting
  static Duration retryInterval = const Duration(seconds: 15);

  Timer? _retryTimer;

  /// Last-seen timeline / focus per task, so the detail screen keeps its
  /// history readable offline (read-through cache).
  final Map<String, List<TaskEvent>> _eventsCache = {};
  final Map<String, FocusHistory> _focusCache = {};

  /// When true, all backend API calls are skipped and the repo works
  /// entirely from the local SharedPreferences cache. Used for guest mode.
  bool get guestMode => _guestMode;
  bool _guestMode = false;

  /// Enable guest mode: stop syncing, work from local cache only.
  Future<void> setGuestMode(bool value) async {
    _guestMode = value;
    if (value) {
      // Stop background retries; guests never sync.
      _retryTimer?.cancel();
    }
    notifyListeners();
  }

  /// Migrate guest tasks into the synced repository after sign-in.
  ///
  /// Each guest entry is created via the normal [createTask] path (full
  /// optimistic + outbox flow), so migration is offline-safe: unreachable
  /// backend just queues the creates for replay. Returns the number of
  /// tasks migrated.
  ///
  /// Idempotent: each successfully migrated entry is dropped from
  /// [GuestStore] as it lands. Without that, a partial migration (one
  /// bad entry, offline backend) would leave the whole list in place, and
  /// the retry on the next auth event would create the already-migrated
  /// tasks a second time.
  Future<int> migrateGuestTasks(
      List<Map<String, dynamic>> guestTasks) async {
    if (guestTasks.isEmpty) return 0;
    var migrated = 0;
    for (final g in guestTasks) {
      final title = (g['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final guestId = g['id'] as String?;
      try {
        final created = await createTask(
          title: title,
          folder: (g['folder'] as String?) ?? 'Productivity',
        );
        if (g['done'] == true) {
          await moveTask(created.id, 'done');
        }
        migrated++;
        // Landed — drop it from the guest store so a retry cannot
        // duplicate it.
        if (guestId != null && guestId.isNotEmpty) {
          await GuestStore.instance.remove(guestId);
        }
      } catch (_) {
        // Stop at the first failure: the remaining entries stay in the
        // guest store and the caller keeps the guest flag set, so the
        // next auth event retries exactly what is still missing.
        break;
      }
    }
    return migrated;
  }

  List<Task> get tasks => List.unmodifiable(_tasks);
  bool get isLoading => _loading;
  String? get error => _error;

  /// Number of mutations waiting to sync — surfaced for UI + tests.
  int get pendingMutations => _outbox.length;
  bool get hasPendingMutations => _outbox.isNotEmpty;

  /// Mutations parked after repeated failures.
  int get deadLetterCount => _deadLetters.length;

  List<Task> get todoTasks => _tasks.where((t) => t.status == 'todo').toList();
  List<Task> get inProgressTasks => _tasks.where((t) => t.status == 'in_progress').toList();
  List<Task> get doneTasks => _tasks.where((t) => t.status == 'done').toList();

  /// Date-aware getters (Master Blueprint Phase 1): prevent "Next Week"
  /// tasks from leaking into Today's view.

  /// Tasks due today, overdue, or with no due date (inbox).
  List<Task> get todayTasks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _tasks.where((t) {
      if (t.status != 'todo') return false;
      if (t.dueAt == null) return true; // inbox/unscheduled
      final due = DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day);
      return !due.isAfter(today); // today or past (overdue)
    }).toList();
  }

  /// Tasks due strictly after today.
  List<Task> get upcomingTasks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _tasks.where((t) {
      if (t.status != 'todo') return false;
      if (t.dueAt == null) return false;
      final due = DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day);
      return due.isAfter(today);
    }).toList();
  }

  /// Tasks due in the next calendar week (Monday to Sunday).
  List<Task> get nextWeekTasks {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Find next Monday
    final daysToMonday = (8 - today.weekday) % 7;
    final nextMonday = today.add(Duration(days: daysToMonday == 0 ? 7 : daysToMonday));
    final nextSunday = nextMonday.add(const Duration(days: 6));
    return _tasks.where((t) {
      if (t.status != 'todo') return false;
      if (t.dueAt == null) return false;
      final due = DateTime(t.dueAt!.year, t.dueAt!.month, t.dueAt!.day);
      return !due.isBefore(nextMonday) && !due.isAfter(nextSunday);
    }).toList();
  }

  /// Tasks with no due date (backlog / someday).
  List<Task> get somedayTasks =>
      _tasks.where((t) => t.status == 'todo' && t.dueAt == null).toList();

  List<Task> tasksForFolder(String folder) =>
      _tasks.where((t) => t.folder.toLowerCase() == folder.toLowerCase()).toList();

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadOutbox();
    await _loadDeadLetters();
    await _loadFromLocalCache();
    bool loggedIn = false;
    try {
      loggedIn = AuthStore.instance.isLoggedIn;
    } catch (_) {
      // Firebase unavailable (widget tests, cold start before
      // Firebase.initializeApp): stay on the local cache and sync later.
      loggedIn = false;
    }
    if (loggedIn) {
      await loadRemote();
    }
  }

  /// Test seam: wipe in-memory state so tests start clean.
  @visibleForTesting
  void debugReset() {
    _tasks = [];
    _outbox.clear();
    _deadLetters.clear();
    _loading = false;
    _error = null;
    _isInitialized = false;
    notifyListeners();
  }

  // --- Offline outbox ------------------------------------------------

  Future<void> _loadOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kOutbox);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _outbox
        ..clear()
        ..addAll(list.map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
  }

  Future<void> _saveOutbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kOutbox, jsonEncode(_outbox));
    } catch (_) {}
  }

  Future<void> _enqueue(Map<String, dynamic> mutation) async {
    mutation['attempts'] = (mutation['attempts'] as int?) ?? 0;
    _outbox.add(mutation);
    await _saveOutbox();
    notifyListeners();
    // Live reconnection: while anything is pending, keep trying in the
    // background (no connectivity plugin required).
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!autoRetry || _retryTimer != null) return;
    _retryTimer = Timer.periodic(retryInterval, (_) async {
      if (_outbox.isEmpty) {
        _cancelRetry();
        return;
      }
      await syncNow();
      if (_outbox.isEmpty) _cancelRetry();
    });
  }

  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _loadDeadLetters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDeadLetters);
      if (raw == null) return;
      final list = jsonDecode(raw) as List;
      _deadLetters
        ..clear()
        ..addAll(list.map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
  }

  Future<void> _saveDeadLetters() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDeadLetters, jsonEncode(_deadLetters));
    } catch (_) {}
  }

  /// Drain the queued mutations now (called on reconnect / app resume).
  /// Safe to call when offline — failures are retained for the next try.
  Future<void> syncNow() async {
    if (_outbox.isEmpty) {
      _cancelRetry();
      return;
    }
    await _drainOutbox();
    if (_outbox.isEmpty) _cancelRetry();
  }

  /// Drop every parked mutation (e.g. after the user acknowledges them).
  Future<void> discardDeadLetters() async {
    if (_deadLetters.isEmpty) return;
    _deadLetters.clear();
    await _saveDeadLetters();
    notifyListeners();
  }

  /// Fresh slate for a new account (logout / account switch / signup).
  /// Clears memory AND disk so the next account never sees the previous
  /// account's tasks or queued mutations. All stores use global prefs
  /// keys, so without this a new login inherits old data.
  Future<void> clearForAccountSwitch() async {
    _cancelRetry();
    _tasks = [];
    _outbox.clear();
    _deadLetters.clear();
    _eventsCache.clear();
    _focusCache.clear();
    _error = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kTasksCache);
      await prefs.remove(_kOutbox);
      await prefs.remove(_kDeadLetters);
    } catch (_) {}
    notifyListeners();
  }

  /// Re-queue parked mutations so the next sync replays them. Used by
  /// the Settings "sync issues" row: a fix on the server (or a login)
  /// makes a previously-fatal mutation valid again.
  Future<void> retryDeadLetters() async {
    if (_deadLetters.isEmpty) return;
    final revived = _deadLetters.map((m) {
      final copy = Map<String, dynamic>.from(m);
      copy['attempts'] = 0;
      return copy;
    }).toList();
    _deadLetters.clear();
    await _saveDeadLetters();
    for (final m in revived) {
      await _enqueue(m);
    }
    await syncNow();
  }

  /// Replays every queued mutation in FIFO order.
  ///
  /// - A network/transient failure stops the drain and keeps the tail so
  ///   ordering is never violated on the next attempt.
  /// - An expired session ([AuthExpiredException]) stops the drain
  ///   untouched — it will retry after re-auth.
  /// - A mutation that fails repeatedly (validation / server error) is
  ///   parked in [_deadLetters] after [_maxAttempts] so it can never
  ///   wedge the queue.
  Future<void> _drainOutbox() async {
    if (_outbox.isEmpty) return;
    final idMap = <String, String>{};
    final subIdMap = <String, String>{};
    final keep = <Map<String, dynamic>>[];
    var stopped = false;
    for (final m in _outbox) {
      if (stopped) {
        keep.add(m);
        continue;
      }
      try {
        await _replayMutation(m, idMap, subIdMap);
      } on AuthExpiredException {
        stopped = true;
        keep.add(m);
      } catch (_) {
        final attempts = ((m['attempts'] as int?) ?? 0) + 1;
        m['attempts'] = attempts;
        if (attempts >= _maxAttempts) {
          _deadLetters.add(m);
          // Dropped from the queue: keep draining the rest.
        } else {
          stopped = true;
          keep.add(m);
        }
      }
    }
    _outbox
      ..clear()
      ..addAll(keep);
    await _saveOutbox();
    await _saveDeadLetters();
    await _saveToLocalCache();
    notifyListeners();
  }

  Future<void> _replayMutation(Map<String, dynamic> m,
      Map<String, String> idMap, Map<String, String> subIdMap) async {
    String resolve(String id) => idMap[id] ?? id;
    String resolveSub(String id) => subIdMap[id] ?? id;
    switch ('${m['kind']}') {
      case 'create':
        final body = Map<String, dynamic>.from(m['body'] as Map);
        final clientId = '${m['clientId']}';
        final created = await _api.createTask(
          '${body['title']}',
          folder: '${body['folder'] ?? 'Productivity'}',
          tag: '${body['tag'] ?? 'General'}',
          description: '${body['description'] ?? ''}',
          priority: '${body['priority'] ?? 'none'}',
          recurring: '${body['recurring'] ?? 'none'}',
          dueAt: body['due_at'] == null
              ? null
              : DateTime.tryParse('${body['due_at']}'),
          clientId: clientId,
        );
        idMap[clientId] = created.id;
        final idx = _tasks.indexWhere((t) => t.id == clientId);
        if (idx != -1) _tasks[idx] = created;
        break;
      case 'move':
        await _api.moveTask(resolve('${m['id']}'), '${m['status']}');
        break;
      case 'update':
        final body = Map<String, dynamic>.from(m['body'] as Map);
        await _api.updateTask(
          resolve('${m['id']}'),
          title: body['title'] as String?,
          description: body['description'] as String?,
          tag: body['tag'] as String?,
          folder: body['folder'] as String?,
          status: body['status'] as String?,
          priority: body['priority'] as String?,
          recurring: body['recurring'] as String?,
          dueAt: body['due_at'] == null
              ? null
              : DateTime.tryParse('${body['due_at']}'),
          clearDue: body['clear_due'] == true,
        );
        break;
      case 'delete':
        await _api.deleteTask(resolve('${m['id']}'));
        break;
      case 'subtask':
        await _api.updateSubtask('${m['id']}', done: m['done'] == true);
        break;
      case 'reorder':
        final updates = (m['updates'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .map((u) => {
                  'id': resolve('${u['id']}'),
                  'position': u['position'],
                })
            .toList();
        await _api.reorderTasks(updates);
        break;
      case 'subtask_create':
        final taskId = resolve('${m['taskId']}');
        final clientId = '${m['clientId']}';
        final created =
            await _api.createSubtask(taskId, '${m['title']}');
        subIdMap[clientId] = created.id;
        _replaceSubtask(taskId, clientId, created, save: false);
        break;
      case 'subtask_delete':
        await _api.deleteSubtask(resolveSub('${m['id']}'));
        break;
      case 'subtask_reorder':
        final ids = (m['ids'] as List).cast<String>();
        for (var i = 0; i < ids.length; i++) {
          await _api.updateSubtask(resolveSub(ids[i]), position: i);
        }
        break;
      case 'note':
        await _api.addNote(resolve('${m['taskId']}'), '${m['body']}');
        break;
    }
  }

  Future<void> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kTasksCache);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _tasks = list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveToLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_tasks
          .map((t) => {
                'id': t.id,
                'title': t.title,
                'tag': t.tag,
                'folder': t.folder,
                'description': t.description,
                'priority': t.priority,
                'recurring': t.recurring,
                'position': t.position,
                'status': t.status,
                'due_at': t.dueAt?.toIso8601String(),
                'avatar_label': t.avatarLabel,
                'comments': t.comments,
                'focus_minutes': t.focusMinutes,
                'subtasks': t.subtasks
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
                'cadence': t.cadence,
                'habit_counted': t.habitCounted,
                'habit_target': t.habitTarget,
                'habit_unit': t.habitUnit,
                'habit_goal_id': t.habitGoalId,
                'habit_icon': t.habitIconIndex,
                'habit_accent': t.habitAccentIndex,
                'habit_paused': t.habitPaused,
                'habit_log': t.habitLog,
                'habit_frozen': t.habitFrozen,
                'habit_frozen_streak': t.habitFrozenStreak,
              })
          .toList());
      await prefs.setString(_kTasksCache, raw);
    } catch (_) {}
  }

  Future<void> loadRemote({bool withDetails = true}) async {
    // Guest mode: never hit the API, just load from local cache.
    if (_guestMode) {
      _loading = true;
      notifyListeners();
      await _loadFromLocalCache();
      _loading = false;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      // Connectivity restored: replay anything queued while offline
      // BEFORE pulling, so the server sees our intent in order.
      await _drainOutbox();
      final remoteTasks = await _api.fetchTasks(withDetails: withDetails);
      _tasks = remoteTasks;
      _loading = false;
      await _saveToLocalCache();
      notifyListeners();
    } catch (e) {
      _loading = false;
      if (e is! AuthExpiredException) {
        _error = 'Could not sync with cloud. Using local offline cache.';
      }
      notifyListeners();
    }
  }

  /// Optimistic creation: task appears instantly in UI.
  Future<Task> createTask({
    required String title,
    String folder = 'Productivity',
    String tag = 'General',
    String description = '',
    String priority = 'none',
    String recurring = 'none',
    DateTime? dueAt,
    String cadence = 'once',
  }) async {
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    // Activation checkpoint: first real task ever (temp rows excluded).
    final isFirst = !_tasks.any((t) => !t.id.startsWith('temp_'));
    final optimisticTask = Task(
      id: tempId,
      title: title.trim(),
      folder: folder.trim(),
      tag: tag.trim(),
      description: description.trim(),
      priority: priority,
      recurring: recurring,
      status: 'todo',
      dueAt: dueAt,
      cadence: cadence,
    );

    // Prepend to memory
    _tasks.insert(0, optimisticTask);
    notifyListeners();
    await _saveToLocalCache();
    BloomAnalytics.taskCreated(isFirst: isFirst);

    // Guest mode: persist locally, never sync.
    if (_guestMode) return optimisticTask;

    try {
      final serverTask = await _api.createTask(
        title,
        folder: folder,
        tag: tag,
        description: description,
        priority: priority,
        recurring: recurring,
        dueAt: dueAt,
        cadence: cadence,
        clientId: tempId,
      );
      final idx = _tasks.indexWhere((t) => t.id == tempId);
      if (idx != -1) {
        _tasks[idx] = serverTask;
      }
      notifyListeners();
      await _saveToLocalCache();
      return serverTask;
    } catch (e) {
      // Offline fallback: keep the optimistic task AND queue the create
      // so it replays (with the same client id) on reconnect.
      await _enqueue({
        'kind': 'create',
        'clientId': tempId,
        'body': {
          'title': title.trim(),
          'folder': folder.trim(),
          'tag': tag.trim(),
          'description': description.trim(),
          'priority': priority,
          'recurring': recurring,
          'cadence': cadence,
          'due_at': dueAt?.toIso8601String(),
        },
      });
      return optimisticTask;
    }
  }

  /// Optimistic move between Kanban columns. Works even when the task is
  /// not (yet) in the local cache — the API call still fires.
  Future<void> moveTask(String id, String newStatus) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    final wasDone = idx != -1 && _tasks[idx].status == 'done';
    if (idx != -1) {
      final old = _tasks[idx];
      if (old.status == newStatus) return;
      _tasks[idx] = old.copyWith(status: newStatus);
      notifyListeners();
      await _saveToLocalCache();
      if (newStatus == 'done' && !wasDone) {
        BloomAnalytics.taskCompleted();
      }
    }

    // Guest mode: persist locally, never sync.
    if (_guestMode) return;

    try {
      final updated = await _api.moveTask(id, newStatus);
      final currIdx = _tasks.indexWhere((t) => t.id == id);
      if (currIdx != -1) {
        _tasks[currIdx] = updated;
        notifyListeners();
      }
    } catch (_) {
      // Offline: keep the optimistic status and queue the move.
      await _enqueue({'kind': 'move', 'id': id, 'status': newStatus});
    }
  }

  /// Optimistic full update (title, description, tags, folder, due date).
  Future<void> updateTask(
    String id, {
    String? title,
    String? description,
    String? tag,
    String? folder,
    String? status,
    String? priority,
    String? recurring,
    DateTime? dueAt,
    bool clearDue = false,
  }) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      final old = _tasks[idx];
      final optimistic = old.copyWith(
        title: title,
        description: description,
        tag: tag,
        folder: folder,
        status: status,
        priority: priority,
        recurring: recurring,
        dueAt: clearDue ? null : (dueAt ?? old.dueAt),
        clearDue: clearDue,
      );
      _tasks[idx] = optimistic;
      notifyListeners();
      await _saveToLocalCache();
    }

    // Guest mode: persist locally, never sync.
    if (_guestMode) return;

    try {
      final updated = await _api.updateTask(
        id,
        title: title,
        description: description,
        tag: tag,
        folder: folder,
        status: status,
        priority: priority,
        recurring: recurring,
        dueAt: dueAt,
        clearDue: clearDue,
      );
      final currIdx = _tasks.indexWhere((t) => t.id == id);
      if (currIdx != -1) {
        _tasks[currIdx] = updated;
        notifyListeners();
      }
    } catch (_) {
      // Offline: keep the optimistic edit and queue it.
      await _enqueue({
        'kind': 'update',
        'id': id,
        'body': {
          'title': title,
          'description': description,
          'tag': tag,
          'folder': folder,
          'status': status,
          'priority': priority,
          'recurring': recurring,
          'due_at': dueAt?.toIso8601String(),
          'clear_due': clearDue,
        },
      });
    }
  }

  /// Optimistic delete. Works even when the task is not in the cache.
  Future<void> deleteTask(String id) async {
    final idx = _tasks.indexWhere((t) => t.id == id);
    if (idx != -1) {
      _tasks.removeAt(idx);
      notifyListeners();
      await _saveToLocalCache();
    }

    // Guest mode: persist locally, never sync.
    if (_guestMode) return;

    try {
      await _api.deleteTask(id);
    } catch (_) {
      // Offline: keep it deleted locally and queue the delete so the
      // server catches up on reconnect (never resurrect it in the UI).
      await _enqueue({'kind': 'delete', 'id': id});
    }
  }

  /// Reorder tasks within Kanban status.
  Future<void> reorder(int oldIndex, int newIndex, String status) async {
    final statusList = _tasks.where((t) => t.status == status).toList();
    if (oldIndex < 0 || oldIndex >= statusList.length) return;
    if (newIndex > statusList.length) newIndex = statusList.length;
    if (oldIndex < newIndex) newIndex -= 1;

    final item = statusList.removeAt(oldIndex);
    statusList.insert(newIndex, item);

    // Update positions
    final updates = <Map<String, dynamic>>[];
    for (int i = 0; i < statusList.length; i++) {
      final t = statusList[i];
      final globalIdx = _tasks.indexWhere((x) => x.id == t.id);
      if (globalIdx != -1) {
        _tasks[globalIdx] = t.copyWith(position: i);
        updates.add({'id': t.id, 'position': i});
      }
    }
    notifyListeners();
    await _saveToLocalCache();

    // Guest mode: persist locally, never sync.
    if (_guestMode) return;

    try {
      await _api.reorderTasks(updates);
    } catch (_) {
      await _enqueue({'kind': 'reorder', 'updates': updates});
    }
  }

  /// Optimistic subtask completion/reopen. The parent task's [subtasks]
  /// list updates instantly; a failed sync queues the toggle.
  Future<void> setSubtaskDone(String subtaskId, bool done) async {
    for (var i = 0; i < _tasks.length; i++) {
      final subs = _tasks[i].subtasks;
      if (subs == null) continue;
      final si = subs.indexWhere((s) => s.id == subtaskId);
      if (si == -1) continue;
      final updated = [...subs];
      updated[si] = subs[si].copyWith(
        done: done,
        completedAt: done ? DateTime.now() : null,
      );
      _tasks[i] = _tasks[i].copyWith(subtasks: updated);
      notifyListeners();
      await _saveToLocalCache();
      break;
    }
    // Guest mode: persist locally, never sync.
    if (_guestMode) return;

    try {
      await _api.updateSubtask(subtaskId, done: done);
    } catch (_) {
      await _enqueue({'kind': 'subtask', 'id': subtaskId, 'done': done});
    }
  }

  /// Optimistic subtask creation. Inserts into the parent task now and
  /// queues on failure (works offline; replays with client-id mapping).
  Future<Subtask> createSubtask(String taskId, String title) async {
    final tempId = 'tmp_sub_${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = Subtask(
      id: tempId,
      taskId: taskId,
      title: title.trim(),
      startedAt: DateTime.now(),
    );
    _applySubtaskInsert(taskId, optimistic);
    await _saveToLocalCache();

    // Guest mode: persist locally, never sync.
    if (_guestMode) return optimistic;

    try {
      final created = await _api.createSubtask(taskId, title.trim());
      _replaceSubtask(taskId, tempId, created);
      await _saveToLocalCache();
      return created;
    } catch (_) {
      await _enqueue({
        'kind': 'subtask_create',
        'taskId': taskId,
        'clientId': tempId,
        'title': title.trim(),
      });
      return optimistic;
    }
  }

  /// Optimistic subtask delete. Works offline (queued).
  Future<void> deleteSubtask(String subtaskId) async {
    _removeSubtaskEverywhere(subtaskId);
    await _saveToLocalCache();
    try {
      await _api.deleteSubtask(subtaskId);
    } catch (_) {
      await _enqueue({'kind': 'subtask_delete', 'id': subtaskId});
    }
  }

  /// Optimistic reorder of a task's subtasks.
  Future<void> reorderSubtasks(String taskId, List<String> orderedIds) async {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx != -1) {
      final subs = _tasks[idx].subtasks;
      if (subs != null) {
        final byId = {for (final s in subs) s.id: s};
        final ordered = <Subtask>[];
        for (var i = 0; i < orderedIds.length; i++) {
          final s = byId[orderedIds[i]];
          if (s != null) ordered.add(s.copyWith(position: i));
        }
        // Preserve any the caller didn't mention.
        for (final s in subs) {
          if (!orderedIds.contains(s.id)) ordered.add(s);
        }
        _tasks[idx] = _tasks[idx].copyWith(subtasks: ordered);
        notifyListeners();
        await _saveToLocalCache();
      }
    }
    try {
      for (var i = 0; i < orderedIds.length; i++) {
        await _api.updateSubtask(orderedIds[i], position: i);
      }
    } catch (_) {
      await _enqueue(
          {'kind': 'subtask_reorder', 'taskId': taskId, 'ids': orderedIds});
    }
  }

  /// Add a progress note to a task's timeline. Returns the stored event,
  /// or null when it was queued offline.
  Future<TaskEvent?> addTaskNote(String taskId, String body) async {
    // Guest mode: notes are local-only.
    if (_guestMode) return null;

    try {
      return await _api.addNote(taskId, body);
    } catch (_) {
      await _enqueue({'kind': 'note', 'taskId': taskId, 'body': body});
      return null;
    }
  }

  // --- read-through cache (timeline / focus / subtasks) ---------------

  /// Subtasks for a task: fresh from the server when reachable, else the
  /// last-known copy held in the task cache.
  Future<List<Subtask>> subtasksFor(String taskId) async {
    final cached = _taskById(taskId)?.subtasks ?? const <Subtask>[];
    if (_guestMode) return cached;
    try {
      final fresh = await _api.fetchSubtasks(taskId);
      _setSubtasks(taskId, fresh);
      return fresh;
    } on AuthExpiredException {
      rethrow;
    } catch (_) {
      return cached;
    }
  }

  /// Task timeline: fresh when reachable, else the last-seen copy.
  Future<List<TaskEvent>> taskEvents(String taskId) async {
    if (_guestMode) return _eventsCache[taskId] ?? const [];
    try {
      final fresh = await _api.fetchTaskEvents(taskId);
      _eventsCache[taskId] = fresh;
      return fresh;
    } on AuthExpiredException {
      rethrow;
    } catch (_) {
      return _eventsCache[taskId] ?? const [];
    }
  }

  /// Focus history: fresh when reachable, else the last-seen copy.
  Future<FocusHistory> taskFocus(String taskId) async {
    if (_guestMode) return _focusCache[taskId] ?? const FocusHistory();
    try {
      final fresh = await _api.fetchTaskFocus(taskId);
      _focusCache[taskId] = fresh;
      return fresh;
    } on AuthExpiredException {
      rethrow;
    } catch (_) {
      return _focusCache[taskId] ?? const FocusHistory();
    }
  }

  Task? _taskById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _setSubtasks(String taskId, List<Subtask> subs) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    _tasks[idx] = _tasks[idx].copyWith(subtasks: subs);
    notifyListeners();
    _saveToLocalCache();
  }

  // --- subtask helpers ------------------------------------------------

  void _applySubtaskInsert(String taskId, Subtask s) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final subs = [...?_tasks[idx].subtasks, s];
    _tasks[idx] = _tasks[idx].copyWith(subtasks: subs);
    notifyListeners();
  }

  void _replaceSubtask(String taskId, String tempId, Subtask s,
      {bool save = true}) {
    final idx = _tasks.indexWhere((t) => t.id == taskId);
    if (idx == -1) return;
    final subs = _tasks[idx].subtasks;
    if (subs == null) return;
    final si = subs.indexWhere((x) => x.id == tempId);
    if (si == -1) return;
    final updated = [...subs];
    updated[si] = s;
    _tasks[idx] = _tasks[idx].copyWith(subtasks: updated);
    notifyListeners();
    if (save) _saveToLocalCache();
  }

  void _removeSubtaskEverywhere(String subtaskId) {
    for (var i = 0; i < _tasks.length; i++) {
      final subs = _tasks[i].subtasks;
      if (subs == null) continue;
      if (!subs.any((s) => s.id == subtaskId)) continue;
      _tasks[i] = _tasks[i]
          .copyWith(subtasks: subs.where((s) => s.id != subtaskId).toList());
      notifyListeners();
      break;
    }
  }
}
