import 'dart:convert';
import 'package:http/http.dart' as http;

import '../theme/sakura_theme.dart';
import 'auth_store.dart';
import 'mock_data.dart';

/// Thin HTTP client for the Node/Express + Postgres backend.
/// Throws when the API is unreachable; screens render honest
/// empty/offline states (never mock data presented as real).
///
/// Auth: every request attaches a fresh Firebase ID Token from [AuthStore]
/// as `Authorization: Bearer ...`. Firebase auto-refreshes it before expiry.
/// A 401 from the backend means the account was deleted or the token is invalid.
class BloomApi {
  // Flutter web (Chrome) -> localhost works. Android emulator needs 10.0.2.2.
  static const String baseUrl = String.fromEnvironment(
    'BLOOM_API',
    defaultValue: 'http://localhost:8080',
  );

  static const Duration timeout = Duration(seconds: 20);

  final http.Client _client;
  BloomApi([http.Client? client]) : _client = client ?? http.Client();

  /// Returns fresh auth headers (Firebase ID token is fetched and possibly
  /// refreshed automatically by the Firebase SDK).
  Future<Map<String, String>> get _headers => AuthStore.instance.authHeaders;

  void _guard(http.Response res, String what) {
    if (res.statusCode == 401) {
      // Firebase token is invalid or account deleted — sign out.
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('$what ${res.statusCode}');
    }
  }

  /// Unauthenticated backend probe for the Settings connection row.
  /// GET /health needs no token — reports DB + Firebase-Admin state so
  /// users can tell "no network" from "server down" from "DB down".
  Future<HealthProbe> probeHealth() async {
    final uri = Uri.parse('$baseUrl/health');
    final res =
        await _client.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      try {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return HealthProbe(
          ok: j['ok'] == true,
          firebaseReady: j['firebaseReady'] == true,
          detail: j['firebaseCredentialSource']?.toString(),
        );
      } catch (_) {
        return const HealthProbe(ok: true, firebaseReady: false);
      }
    }
    return HealthProbe(ok: false, firebaseReady: false, detail: 'HTTP ${res.statusCode}');
  }

  Future<List<Task>> fetchTasks(
      {String? status,
      String? folder,
      bool withDetails = false}) async {
    final q = <String>[];
    if (status != null) q.add('status=$status');
    if (folder != null) q.add('folder=${Uri.encodeComponent(folder)}');
    if (withDetails) q.add('include=subtasks,focus');
    final qs = q.isEmpty ? '' : '?${q.join('&')}';
    final uri = Uri.parse('$baseUrl/api/tasks$qs');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'tasks');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Task> moveTask(String id, String status) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$id');
    final res = await _client
        .patch(uri,
            headers: await _headers,
            body: jsonEncode({'status': status}))
        .timeout(timeout);
    _guard(res, 'move');
    return Task.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Task> updateTask(
    String id, {
    String? title,
    String? description,
    String? tag,
    String? folder,
    String? status,
    String? priority,
    String? recurring,
    int? position,
    DateTime? dueAt,
    bool clearDue = false,
  }) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$id');
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (tag != null) 'tag': tag,
      if (folder != null) 'folder': folder,
      if (status != null) 'status': status,
      if (priority != null) 'priority': priority,
      if (recurring != null) 'recurring': recurring,
      if (position != null) 'position': position,
      if (clearDue) 'due_at': null else if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
    };
    final res = await _client
        .patch(uri, headers: await _headers, body: jsonEncode(body))
        .timeout(timeout);
    _guard(res, 'updateTask');
    return Task.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

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
    final uri = Uri.parse('$baseUrl/api/tasks');
    final res = await _client
        .post(
          uri,
          headers: await _headers,
          body: jsonEncode({
            'title': title,
            'folder': folder,
            'tag': tag,
            'description': description,
            'priority': priority,
            'recurring': recurring,
            if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
            if (clientId != null) 'client_id': clientId,
          }),
        )
        .timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('create ${res.statusCode}');
    }
    return Task.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<BloomFolder>> fetchFolders() async {
    final uri = Uri.parse('$baseUrl/api/folders');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'folders');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => BloomFolder.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BloomFolder> createFolder(String name) async {
    final uri = Uri.parse('$baseUrl/api/folders');
    final res = await _client
        .post(uri,
            headers: await _headers,
            body: jsonEncode({'name': name}))
        .timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 201) {
      throw Exception(res.statusCode == 409 ? 'exists' : 'create ${res.statusCode}');
    }
    return BloomFolder.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<BloomFolder> renameFolder(String oldName, String newName) async {
    final uri = Uri.parse('$baseUrl/api/folders/${Uri.encodeComponent(oldName)}');
    final res = await _client
        .patch(uri, headers: await _headers, body: jsonEncode({'name': newName}))
        .timeout(timeout);
    _guard(res, 'renameFolder');
    return BloomFolder.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> reorderTasks(List<Map<String, dynamic>> items) async {
    final uri = Uri.parse('$baseUrl/api/tasks-reorder');
    final res = await _client
        .patch(uri, headers: await _headers, body: jsonEncode({'items': items}))
        .timeout(timeout);
    _guard(res, 'reorderTasks');
  }

  /// Returns heatmap levels oldest -> newest (weeks*7 values, 0-5).
  Future<List<int>> fetchHeatmap({int weeks = 12}) async {
    final days = await fetchHeatmapFull(weeks: weeks);
    return days.map((d) => d.level).toList();
  }

  /// Full heatmap days with calendar dates + counts (for labels/tooltips).
  Future<List<HeatDay>> fetchHeatmapFull({int weeks = 12}) async {
    final uri = Uri.parse('$baseUrl/api/heatmap?weeks=$weeks');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'heatmap');
    final list = jsonDecode(res.body) as List;
    var days = list
        .map((e) => HeatDay.fromJson(e as Map<String, dynamic>))
        .toList();
    // Pad to a full grid if the backend has gaps.
    final want = weeks * 7;
    if (days.length < want && days.isNotEmpty) {
      final first = days.first.date;
      final missing = want - days.length;
      final pad = List<HeatDay>.generate(
        missing,
        (i) => HeatDay(
            date: first.subtract(Duration(days: missing - i)),
            count: 0,
            level: 0),
      );
      days = [...pad, ...days];
    }
    if (days.length >= want) return days.sublist(days.length - want);
    return days;
  }

  Future<Map<String, int>> fetchProgress() async {    final uri = Uri.parse('$baseUrl/api/progress');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'progress');
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final out = <String, int>{'todo': 0, 'in_progress': 0, 'done': 0};
    for (final row in (j['byStatus'] as List)) {
      out['${row['status']}'] = (row['n'] as num).toInt();
    }
    out['active_days'] = (j['active_days'] as num?)?.toInt() ?? 0;
    out['total'] = (j['total'] as num?)?.toInt() ?? 0;
    out['bestStreak'] = (j['bestStreak'] as num?)?.toInt() ?? 0;
    out['currentStreak'] = (j['currentStreak'] as num?)?.toInt() ?? 0;
    return out;
  }

  // --- Phase A: history ("flow") + subtasks ---

  /// Per-task timeline, oldest first.
  Future<List<TaskEvent>> fetchTaskEvents(String taskId) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/events');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'history');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => TaskEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Global activity feed, newest first.
  Future<List<TaskEvent>> fetchActivity({int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/activity?limit=$limit');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'activity');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => TaskEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Standup-style progress note on a task.
  Future<TaskEvent> addNote(String taskId, String body) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/notes');
    final res = await _client
        .post(uri, headers: await _headers, body: jsonEncode({'body': body}))
        .timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 201) throw Exception('note ${res.statusCode}');
    return TaskEvent.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<Subtask>> fetchSubtasks(String taskId) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/subtasks');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'subtasks');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Subtask.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Subtask> createSubtask(String taskId, String title) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/subtasks');
    final res = await _client
        .post(uri, headers: await _headers, body: jsonEncode({'title': title}))
        .timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 201) throw Exception('subtask ${res.statusCode}');
    return Subtask.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Subtask> updateSubtask(String id, {String? title, bool? done, int? position}) async {
    final uri = Uri.parse('$baseUrl/api/subtasks/$id');
    final res = await _client
        .patch(uri,
            headers: await _headers,
            body: jsonEncode({
              if (title != null) 'title': title,
              if (done != null) 'done': done,
              if (position != null) 'position': position,
            }))
        .timeout(timeout);
    _guard(res, 'subtask');
    return Subtask.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> deleteSubtask(String id) async {
    final uri = Uri.parse('$baseUrl/api/subtasks/$id');
    final res = await _client.delete(uri, headers: await _headers).timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 204) throw Exception('subtask ${res.statusCode}');
  }

  // --- Batch: delete, search, export, password reset ---

  Future<void> deleteTask(String id) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$id');
    final res = await _client.delete(uri, headers: await _headers).timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 204) throw Exception('task ${res.statusCode}');
  }

  Future<void> deleteFolder(String name, {String fallbackFolder = 'Productivity'}) async {
    final uri = Uri.parse(
        '$baseUrl/api/folders/${Uri.encodeComponent(name)}?fallback=${Uri.encodeComponent(fallbackFolder)}');
    final res = await _client.delete(uri, headers: await _headers).timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 204) throw Exception('folder ${res.statusCode}');
  }

  Future<Task> setTaskDue(String id, DateTime? due) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$id');
    final res = await _client
        .patch(uri,
            headers: await _headers,
            body: jsonEncode({'due_at': due?.toUtc().toIso8601String()}))
        .timeout(timeout);
    _guard(res, 'task');
    return Task.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<Task>> searchTasks(String q) async {
    final uri = Uri.parse('$baseUrl/api/tasks/search?q=${Uri.encodeQueryComponent(q)}');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'search');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Raw account dump for export (copy-to-clipboard in Settings).
  Future<Map<String, dynamic>> fetchExport() async {
    final uri = Uri.parse('$baseUrl/api/export');
    final res = await _client.get(uri, headers: await _headers).timeout(const Duration(seconds: 10));
    _guard(res, 'export');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // --- Flows: rules engine (n8n-style WHEN/IF/THEN) ---

  Future<List<FlowRule>> fetchRules() async {
    final uri = Uri.parse('$baseUrl/api/rules');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'flows');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => FlowRule.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<FlowRule> createRule({
    required String name,
    required String trigger,
    Map<String, dynamic> condition = const {},
    required List<Map<String, dynamic>> actions,
  }) async {
    final uri = Uri.parse('$baseUrl/api/rules');
    final res = await _client
        .post(uri,
            headers: await _headers,
            body: jsonEncode(
                {'name': name, 'trigger': trigger, 'condition': condition, 'actions': actions}))
        .timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 201) throw Exception('flow ${res.statusCode}');
    return FlowRule.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<FlowRule> updateRule(
    String id, {
    String? name,
    bool? enabled,
    String? trigger,
    Map<String, dynamic>? condition,
    List<Map<String, dynamic>>? actions,
  }) async {
    final uri = Uri.parse('$baseUrl/api/rules/$id');
    final res = await _client
        .patch(uri,
            headers: await _headers,
            body: jsonEncode({
              if (name != null) 'name': name,
              if (enabled != null) 'enabled': enabled,
              if (trigger != null) 'trigger': trigger,
              if (condition != null) 'condition': condition,
              if (actions != null) 'actions': actions,
            }))
        .timeout(timeout);
    _guard(res, 'flow');
    return FlowRule.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> deleteRule(String id) async {
    final uri = Uri.parse('$baseUrl/api/rules/$id');
    final res = await _client.delete(uri, headers: await _headers).timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 204) throw Exception('flow ${res.statusCode}');
  }

  Future<List<RuleRun>> fetchRuns(String ruleId, {int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/rules/$ruleId/runs?limit=$limit');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'runs');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => RuleRun.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<int> fetchWallet() async {
    final uri = Uri.parse('$baseUrl/api/wallet');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'wallet');
    return (jsonDecode(res.body)['balance'] as num?)?.toInt() ?? 450;
  }

  Future<List<InboxMessage>> fetchInbox({int limit = 50}) async {
    final uri = Uri.parse('$baseUrl/api/inbox?limit=$limit');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'inbox');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => InboxMessage.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<InboxMessage> markInboxRead(String id, bool unread) async {
    final uri = Uri.parse('$baseUrl/api/inbox/$id');
    final res = await _client
        .patch(uri, headers: await _headers, body: jsonEncode({'unread': unread}))
        .timeout(timeout);
    _guard(res, 'inbox');
    return InboxMessage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // --- Theme store (catalog/prices live here; palettes in theme/) ---

  Future<StoreState> fetchStore() async {
    final uri = Uri.parse('$baseUrl/api/store');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'store');
    return StoreState.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Throws [AuthException] with the server message on 402 (poor),
  /// so the UI can show it directly.
  Future<void> buyTheme(String id) async {
    final uri = Uri.parse('$baseUrl/api/store/buy');
    final res = await _client
        .post(uri,
            headers: await _headers, body: jsonEncode({'theme_id': id}))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode == 402) {
      throw AuthException(_storeMsg(res.body));
    }
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception('store ${res.statusCode}');
    }
  }

  Future<void> equipTheme(String id) async {
    final uri = Uri.parse('$baseUrl/api/store/equip');
    final res = await _client
        .post(uri,
            headers: await _headers, body: jsonEncode({'theme_id': id}))
        .timeout(timeout);
    _guard(res, 'store');
  }

  static String _storeMsg(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    return 'Not enough tokens — complete tasks and flows to earn more.';
  }

  // --- Phase B: focus timer ---

  /// Start a focus session, optionally attached to a task. A null
  /// [taskId] starts a "Free Deep Work" session (server migration 017).
  Future<FocusSession> startFocus({
    String? taskId,
    required int minutes,
    required String mode,
  }) async {
    final uri = Uri.parse('$baseUrl/api/focus');
    final res = await _client
        .post(uri,
            headers: await _headers,
            body: jsonEncode({
              if (taskId != null) 'task_id': taskId,
              'minutes': minutes,
              'mode': mode
            }))
        .timeout(timeout);
    if (res.statusCode == 401) {
      AuthStore.instance.logout();
      throw const AuthExpiredException();
    }
    if (res.statusCode != 201) throw Exception('focus ${res.statusCode}');
    return FocusSession.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<FocusSession> finishFocus({
    required String id,
    required bool completed,
    required int actualMinutes,
    String? subtask,
  }) async {
    final uri = Uri.parse('$baseUrl/api/focus/$id');
    final res = await _client
        .patch(uri,
            headers: await _headers,
            body: jsonEncode({
              'completed': completed,
              'actual_minutes': actualMinutes,
              if (subtask != null && subtask.isNotEmpty)
                'subtask': subtask,
            }))
        .timeout(timeout);
    _guard(res, 'focus');
    return FocusSession.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<FocusHistory> fetchTaskFocus(String taskId) async {
    final uri = Uri.parse('$baseUrl/api/tasks/$taskId/focus');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'focus');
    return FocusHistory.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<FocusDay>> fetchFocusSummary({int days = 7}) async {
    final uri = Uri.parse('$baseUrl/api/focus/summary?days=$days');
    final res = await _client.get(uri, headers: await _headers).timeout(timeout);
    _guard(res, 'focus');
    final list = jsonDecode(res.body) as List;
    return list.map((e) => FocusDay.fromJson(e as Map<String, dynamic>)).toList();
  }

  // --- Phase D: insights ---

  Future<Insights> fetchInsights() async {
    final uri = Uri.parse('$baseUrl/api/insights');
    final res = await _client.get(uri, headers: await _headers).timeout(const Duration(seconds: 8));
    _guard(res, 'insights');
    return Insights.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }
}

class BloomFolder {
  final String name;
  final String icon;
  final int total;
  final int completed;

  const BloomFolder({
    required this.name,
    this.icon = 'folder',
    this.total = 0,
    this.completed = 0,
  });

  factory BloomFolder.fromJson(Map<String, dynamic> j) => BloomFolder(
        name: '${j['name']}',
        icon: '${j['icon'] ?? 'folder'}',
        total: (j['total'] as num?)?.toInt() ?? 0,
        completed: (j['completed'] as num?)?.toInt() ?? 0,
      );
}

/// One row of a task's timeline: created, status move, rename, or note.
/// `/api/activity` rows additionally carry [taskTitle].
class TaskEvent {
  final String id;
  final String taskId;
  final String kind; // created | status | renamed | note
  final String? fromStatus;
  final String? toStatus;
  final String body;
  final String? taskTitle;
  final DateTime createdAt;

  const TaskEvent({
    required this.id,
    required this.taskId,
    required this.kind,
    this.fromStatus,
    this.toStatus,
    this.body = '',
    this.taskTitle,
    required this.createdAt,
  });

  factory TaskEvent.fromJson(Map<String, dynamic> j) => TaskEvent(
        id: '${j['id']}',
        taskId: '${j['task_id']}',
        kind: '${j['kind']}',
        fromStatus: j['from_status'] == null ? null : '${j['from_status']}',
        toStatus: j['to_status'] == null ? null : '${j['to_status']}',
        body: '${j['body'] ?? ''}',
        taskTitle: j['task_title'] == null ? null : '${j['task_title']}',
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );
}

/// Single-level checklist item under a parent task.
///
/// Completion is one-way: [completedAt] is set once by the server and
/// the API rejects un-checking afterwards. `created_at` is the start.
class Subtask {
  final String id;
  final String taskId;
  final String title;
  final bool done;
  final int position;
  final DateTime startedAt;
  final DateTime? completedAt;

  const Subtask({
    required this.id,
    required this.taskId,
    required this.title,
    this.done = false,
    this.position = 0,
    required this.startedAt,
    this.completedAt,
  });

  factory Subtask.fromJson(Map<String, dynamic> j) {
    final rawDone = j['done'];
    return Subtask(
      id: '${j['id']}',
      taskId: '${j['task_id']}',
      title: '${j['title']}',
      done: rawDone is bool ? rawDone : '$rawDone'.toLowerCase() == 'true',
      position: (j['position'] as num?)?.toInt() ?? 0,
      startedAt: DateTime.tryParse('${j['created_at']}') ??
          DateTime.tryParse('${j['started_at']}') ??
          DateTime.now(),
      completedAt: j['completed_at'] == null
          ? null
          : DateTime.tryParse('${j['completed_at']}'),
    );
  }

  Subtask copyWith(
          {String? title,
          bool? done,
          int? position,
          DateTime? completedAt}) =>
      Subtask(
        id: id,
        taskId: taskId,
        title: title ?? this.title,
        done: done ?? this.done,
        position: position ?? this.position,
        startedAt: startedAt,
        completedAt: completedAt ?? this.completedAt,
      );
}

/// One automation: WHEN [trigger] + IF [condition] THEN [actions].
/// The flow canvas edits exactly this shape.
class FlowRule {
  final String id;
  final String name;
  final bool enabled;
  final String trigger;
  final Map<String, dynamic> condition;
  final List<Map<String, dynamic>> actions;
  final DateTime createdAt;

  const FlowRule({
    required this.id,
    required this.name,
    this.enabled = true,
    required this.trigger,
    this.condition = const {},
    this.actions = const [],
    required this.createdAt,
  });

  factory FlowRule.fromJson(Map<String, dynamic> j) => FlowRule(
        id: '${j['id']}',
        name: '${j['name']}',
        enabled: j['enabled'] is bool
            ? j['enabled'] as bool
            : '${j['enabled']}'.toLowerCase() == 'true',
        trigger: '${j['trigger']}',
        condition: j['condition'] is Map
            ? Map<String, dynamic>.from(j['condition'] as Map)
            : {},
        actions: j['actions'] is List
            ? (j['actions'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList()
            : [],
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'trigger': trigger,
        'condition': condition,
        'actions': actions,
      };
}

/// One recorded firing of a rule: success | skipped | failed.
class RuleRun {
  final String id;
  final String ruleId;
  final String? taskId;
  final String taskTitle;
  final String status;
  final Map<String, dynamic> detail;
  final DateTime createdAt;

  const RuleRun({
    required this.id,
    required this.ruleId,
    this.taskId,
    this.taskTitle = '',
    required this.status,
    this.detail = const {},
    required this.createdAt,
  });

  factory RuleRun.fromJson(Map<String, dynamic> j) => RuleRun(
        id: '${j['id']}',
        ruleId: '${j['rule_id']}',
        taskId: j['task_id'] == null ? null : '${j['task_id']}',
        taskTitle: '${j['task_title'] ?? ''}',
        status: '${j['status']}',
        detail: j['detail'] is Map
            ? Map<String, dynamic>.from(j['detail'] as Map)
            : {},
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      );
}

/// One live inbox message (replaces the old static mock items).
class InboxMessage {
  final String id;
  final String tag;
  final String title;
  final String body;
  final bool unread;
  final DateTime createdAt;

  const InboxMessage({
    required this.id,
    required this.tag,
    required this.title,
    this.body = '',
    this.unread = true,
    required this.createdAt,
  });

  factory InboxMessage.fromJson(Map<String, dynamic> j) {
    final raw = j['unread'];
    return InboxMessage(
      id: '${j['id']}',
      tag: '${j['tag'] ?? 'UPDATE'}',
      title: '${j['title']}',
      body: '${j['body'] ?? ''}',
      unread: raw is bool ? raw : '$raw'.toLowerCase() == 'true',
      createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
    );
  }
}

/// Human labels for the canvas + lists (single source of truth).
String triggerLabel(String t) {
  switch (t) {
    case 'task_created':
      return 'Task created';
    case 'task_moved':
      return 'Task moved';
    case 'task_done':
      return 'Task completed';
    case 'note_added':
      return 'Note added';
    case 'subtasks_complete':
      return 'Checklist finished';
    case 'focus_done':
      return 'Focus finished';
    default:
      return t;
  }
}

String actionLabel(Map<String, dynamic> a) {
  switch (a['type']) {
    case 'award_tokens':
      return '+${a['amount'] ?? 10} tokens';
    case 'inbox':
      return 'Inbox: ${a['title'] ?? 'message'}';
    case 'move_task':
      return 'Move to ${_prettyActionStatus('${a['status'] ?? 'done'}')}';
    case 'complete_parent':
      return 'Complete parent';
    default:
      return '${a['type']}';
  }
}

String _prettyActionStatus(String s) {
  switch (s) {
    case 'in_progress':
      return 'In Progress';
    case 'todo':
      return 'To-Do';
    default:
      return 'Done';
  }
}

/// One heatmap day: calendar date + contributions + color level 0-5.
class HeatDay {
  final DateTime date;
  final int count;
  final int level;

  const HeatDay({required this.date, this.count = 0, this.level = 0});

  factory HeatDay.fromJson(Map<String, dynamic> j) => HeatDay(
        date: DateTime.tryParse('${j['date']}') ?? DateTime.now(),
        count: (j['count'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 0,
      );
}

/// One timer run — attached to a task, or free ("Free Deep Work" when
/// [taskId] is null; server migration 017).
class FocusSession {
  final String id;
  final String? taskId;
  final String mode; // focus | break
  final int plannedMinutes;
  final int actualMinutes;
  final bool completed;
  final DateTime startedAt;

  const FocusSession({
    required this.id,
    this.taskId,
    this.mode = 'focus',
    this.plannedMinutes = 25,
    this.actualMinutes = 0,
    this.completed = false,
    required this.startedAt,
  });

  factory FocusSession.fromJson(Map<String, dynamic> j) {
    final raw = j['completed'];
    return FocusSession(
      id: '${j['id']}',
      taskId: j['task_id'] == null ? null : '${j['task_id']}',
      mode: '${j['mode'] ?? 'focus'}',
      plannedMinutes: (j['planned_minutes'] as num?)?.toInt() ?? 25,
      actualMinutes: (j['actual_minutes'] as num?)?.toInt() ?? 0,
      completed:
          raw is bool ? raw : '$raw'.toLowerCase() == 'true',
      startedAt: DateTime.tryParse('${j['started_at']}') ?? DateTime.now(),
    );
  }
}

/// History + totals for one task's timer runs.
class FocusHistory {
  final List<FocusSession> sessions;
  final int totalSessions;
  final int totalMinutes;
  final int completedCount;

  const FocusHistory({
    this.sessions = const [],
    this.totalSessions = 0,
    this.totalMinutes = 0,
    this.completedCount = 0,
  });

  factory FocusHistory.fromJson(Map<String, dynamic> j) => FocusHistory(
        sessions: j['sessions'] is List
            ? (j['sessions'] as List)
                .map((e) =>
                    FocusSession.fromJson(e as Map<String, dynamic>))
                .toList()
            : [],
        totalSessions:
            (j['totals']?['sessions'] as num?)?.toInt() ?? 0,
        totalMinutes:
            (j['totals']?['minutes'] as num?)?.toInt() ?? 0,
        completedCount:
            (j['totals']?['completed'] as num?)?.toInt() ?? 0,
      );
}

/// One day of focus totals (Phase D insights feed).
class FocusDay {
  final String date;
  final int minutes;
  final int sessions;

  const FocusDay({required this.date, this.minutes = 0, this.sessions = 0});

  factory FocusDay.fromJson(Map<String, dynamic> j) => FocusDay(
        date: '${j['date']}',
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
        sessions: (j['sessions'] as num?)?.toInt() ?? 0,
      );
}

/// Completion split for one tag or folder.
class SplitStat {
  final String name;
  final int total;
  final int done;

  const SplitStat({required this.name, this.total = 0, this.done = 0});

  double get rate => total == 0 ? 0 : done / total;

  factory SplitStat.fromJson(Map<String, dynamic> j, String key) =>
      SplitStat(
        name: '${j[key] ?? '?'}',
        total: (j['total'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
      );
}

/// Whole Phase D payload: numbers in, plain-language insights out
/// (computed on the client in [buildInsights]).
class Insights {
  final List<SplitStat> byTag;
  final List<SplitStat> byFolder;
  final int cycleN;
  final double cycleAvgHours;
  final double cycleMedianHours;
  final List<Map<String, int>> hours; // [{h, n}]
  final int focusMinutes7;
  final int focusSessions7;
  final List<FocusDay> focusDays;
  final int streakBest30;
  final int streakCurrent;

  const Insights({
    this.byTag = const [],
    this.byFolder = const [],
    this.cycleN = 0,
    this.cycleAvgHours = 0,
    this.cycleMedianHours = 0,
    this.hours = const [],
    this.focusMinutes7 = 0,
    this.focusSessions7 = 0,
    this.focusDays = const [],
    this.streakBest30 = 0,
    this.streakCurrent = 0,
  });

  factory Insights.fromJson(Map<String, dynamic> j) => Insights(
        byTag: j['byTag'] is List
            ? (j['byTag'] as List)
                .map((e) => SplitStat.fromJson(
                    e as Map<String, dynamic>, 'tag'))
                .toList()
            : [],
        byFolder: j['byFolder'] is List
            ? (j['byFolder'] as List)
                .map((e) => SplitStat.fromJson(
                    e as Map<String, dynamic>, 'folder'))
                .toList()
            : [],
        cycleN: (j['cycle']?['n'] as num?)?.toInt() ?? 0,
        cycleAvgHours:
            (j['cycle']?['avg_hours'] as num?)?.toDouble() ?? 0,
        cycleMedianHours:
            (j['cycle']?['median_hours'] as num?)?.toDouble() ?? 0,
        hours: j['hours'] is List
            ? (j['hours'] as List)
                .map((e) => {
                      'h': (e['h'] as num?)?.toInt() ?? 0,
                      'n': (e['n'] as num?)?.toInt() ?? 0,
                    })
                .toList()
            : [],
        focusMinutes7:
            (j['focus7']?['minutes'] as num?)?.toInt() ?? 0,
        focusSessions7:
            (j['focus7']?['sessions'] as num?)?.toInt() ?? 0,
        focusDays: j['focusDays'] is List
            ? (j['focusDays'] as List)
                .map((e) =>
                    FocusDay.fromJson(e as Map<String, dynamic>))
                .toList()
            : [],
        streakBest30:
            (j['streak']?['best30'] as num?)?.toInt() ?? 0,
        streakCurrent:
            (j['streak']?['current'] as num?)?.toInt() ?? 0,
      );
}

String _fmtDuration(double hours) {
  if (hours < 1) return '${(hours * 60).round()} min';
  if (hours < 48) {
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
  return '${(hours / 24).toStringAsFixed(1)} days';
}

/// Result of an unauthenticated GET /health probe (Settings row).
class HealthProbe {
  final bool ok;
  final bool firebaseReady;
  final String? detail;

  const HealthProbe({required this.ok, required this.firebaseReady, this.detail});
}

/// Rule-based personal feedback. Pure function of [Insights] — no ML,
/// just your own numbers talking back. Test-covered in phase_a_test.
List<String> buildInsights(Insights ins) {
  final out = <String>[];
  final total =
      ins.byTag.fold<int>(0, (a, s) => a + s.total);
  final done = ins.byTag.fold<int>(0, (a, s) => a + s.done);
  if (total == 0) {
    return ['Complete a few tasks and your patterns will appear here.'];
  }
  out.add(
      'You finish ${(100 * done / total).round()}% of all tasks ($done/$total).');

  final rated =
      ins.byTag.where((s) => s.total >= 2).toList()
        ..sort((a, b) => b.rate.compareTo(a.rate));
  if (rated.length >= 2) {
    out.add(
        '${rated.first.name} is your strength at ${(100 * rated.first.rate).round()}% — ${rated.last.name} stalls at ${(100 * rated.last.rate).round()}%.');
  } else if (rated.length == 1) {
    out.add(
        '${rated.first.name} runs at ${(100 * rated.first.rate).round()}% completion.');
  }

  if (ins.cycleN > 0) {
    out.add(
        'Median idea-to-done: ${_fmtDuration(ins.cycleMedianHours)} across ${ins.cycleN} tasks (30d).');
  } else {
    out.add('No completions in 30 days — the cycle clock starts at your next Done.');
  }

  if (ins.hours.isNotEmpty) {
    final peak = ins.hours.reduce((a, b) => a['n']! >= b['n']! ? a : b);
    out.add(
        'Your peak finishing hour is ${peak['h']}:00 — protect it for deep work.');
  }

  if (ins.focusSessions7 > 0) {
    out.add(
        '${ins.focusMinutes7} min of focus in 7 days across ${ins.focusSessions7} sessions.');
  } else {
    out.add('No focus sessions this week — start one from any task.');
  }

  if (ins.streakCurrent > 1) {
    out.add(
        'Current streak: ${ins.streakCurrent} days (best 30d: ${ins.streakBest30}).');
  } else if (ins.streakBest30 > 1) {
    out.add(
        'Streak paused — your best 30-day run is ${ins.streakBest30} days.');
  }
  return out;
}
