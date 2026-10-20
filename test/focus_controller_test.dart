// FocusController lifecycle: start / pause / resume / adjust / finish /
// abandon, plus the mm:ss formatter. Uses the controller's API seam so
// the session lifecycle runs without a backend.
import 'package:daily_bloom/data/api_client.dart';
import 'package:daily_bloom/data/auth_store.dart';
import 'package:daily_bloom/data/focus_controller.dart';
import 'package:daily_bloom/data/mock_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeFocusApi extends BloomApi {
  int starts = 0;
  int finishes = 0;
  bool failFinish = false;

  @override
  Future<FocusSession> startFocus({
    String? taskId,
    required int minutes,
    required String mode,
  }) async {
    starts++;
    return FocusSession(
      id: 's$starts',
      taskId: taskId,
      mode: mode,
      plannedMinutes: minutes,
      startedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<FocusSession> finishFocus({
    required String id,
    required bool completed,
    required int actualMinutes,
    String? subtask,
  }) async {
    if (failFinish) throw Exception('offline');
    finishes++;
    return FocusSession(
      id: id,
      taskId: 't',
      completed: completed,
      actualMinutes: actualMinutes,
      startedAt: DateTime(2026, 1, 1),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fc = FocusController.instance;
  late _FakeFocusApi api;

  // One fake instance for the whole file: FocusController caches the first
  // object its factory returns, so tests toggle fields on that object.
  setUpAll(() {
    api = _FakeFocusApi();
    FocusController.apiFactory = () => api;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api.failFinish = false;
    api.starts = 0;
    api.finishes = 0;
    if (fc.active) await fc.abandon();
  });

  const task = Task(id: 't1', title: 'Write the spec', tag: 'Work');

  test('formatCountdown pads and clamps', () {
    expect(formatCountdown(const Duration(seconds: 65)), '01:05');
    expect(formatCountdown(const Duration(minutes: 25)), '25:00');
    expect(formatCountdown(const Duration(seconds: -5)), '00:00');
    expect(formatCountdown(Duration.zero), '00:00');
  });

  test('start / pause / resume / adjust clamps, abandon clears', () async {
    await fc.start(task: task, minutes: 25, mode: 'focus');
    expect(fc.active, isTrue);
    expect(fc.task?.id, 't1');
    expect(fc.remaining, const Duration(minutes: 25));
    expect(fc.mode, 'focus');

    fc.pause();
    expect(fc.paused, isTrue);
    fc.resume();
    expect(fc.paused, isFalse);

    fc.adjustTime(const Duration(minutes: -60));
    expect(fc.remaining, const Duration(minutes: 1), reason: '1 min floor');
    fc.adjustTime(const Duration(hours: 20));
    expect(fc.remaining, const Duration(hours: 8), reason: '8 h ceiling');

    await fc.abandon();
    expect(fc.active, isFalse);
  });

  test('starting while a session is active throws', () async {
    await fc.start(task: task, minutes: 5, mode: 'focus');
    await expectLater(
      () => fc.start(task: task, minutes: 5, mode: 'focus'),
      throwsA(isA<AuthException>()),
    );
    await fc.abandon();
  });

  test('free focus starts without a task and finishes cleanly', () async {
    await fc.start(minutes: 10, mode: 'focus');
    expect(fc.active, isTrue);
    expect(fc.task, isNull);
    expect(api.starts, 1);
    await fc.finish();
    expect(fc.active, isFalse);
    expect(fc.consumeNotice(), contains('Focused'));
  });

  test('finish posts the session and emits a focus notice', () async {
    await fc.start(task: task, minutes: 25, mode: 'focus');
    final before = api.finishes;
    await fc.finish();
    expect(api.finishes, before + 1);
    expect(fc.active, isFalse);
    expect(fc.consumeNotice(), contains('Focused'));
    expect(fc.consumeNotice(), isNull, reason: 'notice is one-shot');
  });

  test('finish reports a save failure without crashing', () async {
    await fc.start(task: task, minutes: 25, mode: 'focus');
    api.failFinish = true;
    await fc.finish();
    expect(fc.active, isFalse);
    expect(fc.consumeNotice(), contains('Could not save'));
  });

  test('task-linked finish offers the Mark done payoff id', () async {
    await fc.start(task: task, minutes: 25, mode: 'focus');
    await fc.finish();
    // The payoff loop: a finished, task-linked focus session surfaces the
    // task id so the mini-player can offer a one-tap "Mark done".
    expect(fc.noticeTaskId, 't1');
    fc.consumeNotice();
    expect(fc.noticeTaskId, isNull, reason: 'payoff id is consumed too');
  });

  test('free focus and break sessions offer no Mark done payoff', () async {
    await fc.start(minutes: 10, mode: 'focus');
    await fc.finish();
    expect(fc.noticeTaskId, isNull, reason: 'no task to complete');
    fc.consumeNotice();

    await fc.start(task: task, minutes: 5, mode: 'break');
    await fc.finish();
    expect(fc.noticeTaskId, isNull, reason: 'a break never completes a task');
    fc.consumeNotice();
  });

  test('abandon banks partial minutes instead of discarding', () async {
    await fc.start(task: task, minutes: 10, mode: 'break');
    await fc.abandon();
    expect(fc.active, isFalse);
    final note = fc.consumeNotice() ?? '';
    // Immediate abandon banks nothing; either way the copy credits
    // the user instead of saying "discarded".
    expect(note, isNot(contains('discarded')));
    expect(note, anyOf([contains('banked'), contains('nothing lost')]));
  });
}
