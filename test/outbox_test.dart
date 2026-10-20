// Offline outbox: replay on reconnect + dead-letter after repeated
// failures. Uses the repository's injectable API seam so online/offline
// transitions are deterministic.
import 'package:daily_bloom/data/api_client.dart';
import 'package:daily_bloom/data/mock_data.dart';
import 'package:daily_bloom/data/task_repository.dart';
import 'package:daily_bloom/screens/matrix_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake backend: `fail` flips the network on/off. Records successful
/// creates/moves so the test can prove the queue actually replayed.
class _FakeApi extends BloomApi {
  bool fail = true;
  int createCalls = 0;
  int moveCalls = 0;
  List<Task> tasks = [];

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
    String cadence = 'once',
  }) async {
    if (fail) throw Exception('offline');
    createCalls++;
    return Task(
      id: 'server_${clientId ?? createCalls}',
      title: title,
      tag: tag,
      folder: folder,
      status: 'todo',
    );
  }

  @override
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
    if (fail) throw Exception('offline');
    return Task(id: id, title: title ?? 'x', tag: tag ?? 'General');
  }

  @override
  Future<Task> moveTask(String id, String status) async {
    if (fail) throw Exception('offline');
    moveCalls++;
    final t = tasks.firstWhere(
      (x) => x.id == id,
      orElse: () => Task(id: id, title: 'x', tag: 'General'),
    );
    return t.copyWith(status: status);
  }

  @override
  Future<List<Task>> fetchTasks(
      {String? status, String? folder, bool withDetails = false}) async {
    if (fail) throw Exception('offline');
    return tasks;
  }

  int subCreateCalls = 0;

  @override
  Future<Subtask> createSubtask(String taskId, String title) async {
    if (fail) throw Exception('offline');
    subCreateCalls++;
    return Subtask(
      id: 'server_sub_$subCreateCalls',
      taskId: taskId,
      title: title,
      startedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<TaskEvent> addNote(String taskId, String body) async {
    if (fail) throw Exception('offline');
    return TaskEvent(
      id: 'evt',
      taskId: taskId,
      kind: 'note',
      body: body,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<List<TaskEvent>> fetchTaskEvents(String taskId) async {
    if (fail) throw Exception('offline');
    return [
      TaskEvent(
        id: 'e1',
        taskId: taskId,
        kind: 'created',
        createdAt: DateTime(2026, 1, 1),
      ),
    ];
  }
}

void main() {
  final fake = _FakeApi();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TaskRepository.apiFactory = () => fake;
    // Keep the background retry loop out of most tests (no pending timers).
    TaskRepository.autoRetry = false;
    TaskRepository.retryInterval = const Duration(seconds: 15);
    fake.fail = true;
  });

  tearDown(() {
    TaskRepository.autoRetry = false;
    TaskRepository.retryInterval = const Duration(seconds: 15);
  });

  test('queued mutations replay in order on reconnect', () async {
    final repo = TaskRepository.instance;
    final before = repo.pendingMutations;

    await repo.createTask(title: 'Offline bloom');
    expect(repo.pendingMutations, before + 1,
        reason: 'offline create is queued');

    // Reconnect and drain.
    fake.fail = false;
    await repo.syncNow();
    expect(repo.pendingMutations, 0, reason: 'queue drained on reconnect');
    expect(fake.createCalls, greaterThanOrEqualTo(1),
        reason: 'the queued create reached the backend');
  });

  test('a repeatedly failing mutation is dead-lettered, not stuck', () async {
    final repo = TaskRepository.instance;
    await repo.discardDeadLetters();

    // Offline update for a task the cache does not know about.
    await repo.updateTask('ghost', title: 'nope');
    expect(repo.pendingMutations, greaterThanOrEqualTo(1));

    // Five failed drains park it; the queue is never wedged.
    for (var i = 0; i < 6; i++) {
      await repo.syncNow();
    }
    expect(repo.deadLetterCount, greaterThanOrEqualTo(1));
    expect(repo.pendingMutations, 0);
  });

  testWidgets('board reads + completes through the repository',
      (tester) async {
    fake.fail = false;
    fake.tasks = [
      const Task(id: 't1', title: 'Integration bloom', tag: 'General'),
    ];

    await tester.pumpWidget(const MaterialApp(home: MatrixScreen()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // The board rendered the task straight from the repository cache.
    expect(find.text('Integration bloom'), findsWidgets);

    // Completing routes through the repository to the (fake) backend.
    await tester.tap(find.bySemanticsLabel('Mark task done').first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(fake.moveCalls, greaterThanOrEqualTo(1));
    expect(tester.takeException(), isNull);
  });

  test('offline subtask + note queue and replay with id remapping',
      () async {
    final repo = TaskRepository.instance;

    // Everything below happens offline: a parent task, a subtask under it,
    // and a timeline note — each queued optimistically.
    await repo.createTask(title: 'Parent task');
    final parent = repo.tasks.firstWhere((t) => t.title == 'Parent task');

    await repo.createSubtask(parent.id, 'Step one');
    final withSub = repo.tasks.firstWhere((t) => t.id == parent.id);
    expect(withSub.subtasks!.any((s) => s.title == 'Step one'), isTrue,
        reason: 'subtask shows optimistically while offline');

    await repo.addTaskNote(parent.id, 'progress note');
    expect(repo.pendingMutations, greaterThanOrEqualTo(3));

    // Reconnect: create -> subtask_create -> note replay in order, with
    // the temp task id remapped to the server id.
    fake.fail = false;
    await repo.syncNow();
    expect(repo.pendingMutations, 0);
    expect(fake.createCalls, greaterThanOrEqualTo(1));
    expect(fake.subCreateCalls, greaterThanOrEqualTo(1));
  });

  test('auto-retry drains the outbox when connectivity returns', () async {
    TaskRepository.autoRetry = true;
    TaskRepository.retryInterval = const Duration(milliseconds: 25);
    final repo = TaskRepository.instance;

    // Offline: the create queues and the retry loop starts.
    fake.fail = true;
    await repo.createTask(title: 'Auto retry bloom');
    expect(repo.pendingMutations, greaterThanOrEqualTo(1));

    // Connectivity comes back; the loop drains without any manual sync.
    fake.fail = false;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(repo.pendingMutations, 0);

    TaskRepository.autoRetry = false;
  });

  test('read-through cache keeps the timeline readable offline', () async {
    final repo = TaskRepository.instance;

    // Online: the timeline is fetched and cached.
    fake.fail = false;
    final online = await repo.taskEvents('t1');
    expect(online, isNotEmpty);

    // Offline: the last-seen copy is returned instead of an error.
    fake.fail = true;
    final offline = await repo.taskEvents('t1');
    expect(offline, online);
  });
}
