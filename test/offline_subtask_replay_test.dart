import 'package:daily_bloom/data/api_client.dart';
import 'package:daily_bloom/data/mock_data.dart';
import 'package:daily_bloom/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeApi extends BloomApi {
  bool fail = true;
  int subCreateCalls = 0;
  int subUpdateCalls = 0;
  int subDeleteCalls = 0;

  @override
  Future<Task> createTask(String title, {String folder = 'Productivity', String tag = 'General', String description = '', String priority = 'none', String recurring = 'none', DateTime? dueAt, String? clientId, String cadence = 'once'}) async {
    if (fail) throw Exception('offline');
    return Task(id: 'server_${clientId ?? title}', title: title, tag: tag, folder: folder, status: 'todo');
  }

  @override
  Future<Subtask> createSubtask(String taskId, String title) async {
    if (fail) throw Exception('offline');
    subCreateCalls++;
    return Subtask(id: 'server_sub_$subCreateCalls', taskId: taskId, title: title, startedAt: DateTime(2026, 1, 1));
  }

  @override
  Future<Subtask> updateSubtask(String id, {String? title, bool? done, int? position}) async {
    if (fail) throw Exception('offline');
    subUpdateCalls++;
    return Subtask(id: id, taskId: 't', title: title ?? 'x', done: done ?? false, position: position ?? 0, startedAt: DateTime(2026, 1, 1));
  }

  @override
  Future<void> deleteSubtask(String id) async {
    if (fail) throw Exception('offline');
    subDeleteCalls++;
  }

  @override
  Future<List<Task>> fetchTasks({String? status, String? folder, bool withDetails = false}) async {
    if (fail) throw Exception('offline');
    return [];
  }
}

void main() {
  final fake = _FakeApi();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TaskRepository.apiFactory = () => fake;
    TaskRepository.autoRetry = false;
    fake.fail = true;
    TaskRepository.instance.debugReset();
  });

  test('offline subtask toggle replays with id remapping', () async {
    final repo = TaskRepository.instance;
    await repo.createTask(title: 'Parent');
    final parent = repo.tasks.firstWhere((t) => t.title == 'Parent');
    await repo.createSubtask(parent.id, 'Step');
    final withSub = repo.tasks.firstWhere((t) => t.id == parent.id);
    final sub = withSub.subtasks!.first;
    await repo.setSubtaskDone(sub.id, true);
    fake.fail = false;
    await repo.syncNow();
    expect(repo.pendingMutations, 0);
    expect(fake.subUpdateCalls, greaterThanOrEqualTo(1));
  });

  test('offline subtask delete replays', () async {
    final repo = TaskRepository.instance;
    await repo.createTask(title: 'Parent');
    final parent = repo.tasks.firstWhere((t) => t.title == 'Parent');
    await repo.createSubtask(parent.id, 'Step');
    final withSub = repo.tasks.firstWhere((t) => t.id == parent.id);
    final sub = withSub.subtasks!.first;
    await repo.deleteSubtask(sub.id);
    fake.fail = false;
    await repo.syncNow();
    expect(repo.pendingMutations, 0);
    expect(fake.subDeleteCalls, greaterThanOrEqualTo(1));
  });
}
