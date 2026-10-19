import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'analytics.dart';
import 'ambient_sound.dart';
import 'auth_store.dart';
import 'mock_data.dart';
import 'reminders.dart';
import 'session_sound.dart';
import '../game/first_week_arc.dart';

/// mm:ss for the countdown pills.
String formatCountdown(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final m = total ~/ 60;
  final s = total % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// App-wide focus timer. A singleton like [AuthStore], so the countdown
/// survives navigation: start it on a task, browse anywhere, finish
/// from the mini-player. Remaining time is recomputed from a deadline
/// ([endsAt]) on every tick, so background throttling can't drift it.
///
/// Perf: two notifiers in one —
/// - [tickListenable]: fires every second while running. ONLY the visible
///   countdown text listens (mini-player + timer screen digits). No cards.
/// - [ChangeNotifier] (this): fires on structural changes (start/pause/
///   finish/task switch). Cards + shell listen here — max 1 rebuild per
///   user action, never per second.
///
/// A restart drops the live countdown (documented v1 limit) — the
/// server row stays, and can be finished/abandoned from history later.
class FocusController extends ChangeNotifier {
  FocusController._();
  static final FocusController instance = FocusController._();

  /// Test seam: swap the API implementation to drive the session
  /// lifecycle without a backend. Production leaves the default.
  @visibleForTesting
  static BloomApi Function() apiFactory = BloomApi.new;

  late final _api = apiFactory();
  Timer? _ticker;

  String? sessionId;
  Task? task;
  String? subtaskTitle;
  String mode = 'focus';
  int plannedMinutes = 25;
  Duration remaining = Duration.zero;
  bool paused = false;
  bool busy = false;

  /// Ticks every second while a session runs. Countdown labels listen to
  /// this; everything else listens to the controller itself.
  final ValueNotifier<int> tickListenable = ValueNotifier<int>(0);

  /// Structural changes + per-second ticks. Use only for small subtrees
  /// whose whole body IS the countdown (timer screen). Dense lists and
  /// cards must listen to the controller alone, then scope the tick to
  /// the digit label with a [ValueListenableBuilder].
  late final Listenable uiListenable =
      Listenable.merge([this, tickListenable]);

  /// One-shot message for the mini-player to show as a snackbar.
  String? notice;

  bool get active => sessionId != null;

  String? consumeNotice() {
    final n = notice;
    notice = null;
    return n;
  }

  Future<void> start({
    Task? task,
    required int minutes,
    required String mode,
    String? subtaskTitle,
  }) async {
    if (active) throw const AuthException('Finish the current session first.');
    busy = true;
    notifyListeners();
    BloomAnalytics.focusStarted(minutes: minutes);
    try {
      final s = await _api.startFocus(
          taskId: task?.id, minutes: minutes, mode: mode);
      sessionId = s.id;
      this.task = task;
      this.subtaskTitle = subtaskTitle?.trim().isEmpty == true
          ? null
          : subtaskTitle?.trim();
      plannedMinutes = minutes;
      this.mode = mode;
      remaining = Duration(minutes: minutes);
      paused = false;
      _tick();
      // Background alarm: the in-memory ticker dies with the app, so the
      // OS fires the completion notice even when locked/backgrounded.
      unawaited(ReminderService.instance.scheduleFocusTimerNotification(
        duration: remaining,
        label: task?.title ?? 'Free Deep Work',
      ));
      // Ambient wash follows the session when the user opted in.
      unawaited(AmbientSound.sync(playing: true));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _tick() {
    _ticker?.cancel();
    final endsAt = DateTime.now().add(remaining);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      remaining = endsAt.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        remaining = Duration.zero;
        // Structural change (session ending) → full notify, then finish.
        notifyListeners();
        finish(); // timer ran out: complete the session
        return;
      }
      // Per-second tick → ONLY the countdown labels rebuild.
      tickListenable.value++;
    });
  }

  void pause() {
    if (!active || paused) return;
    _ticker?.cancel();
    paused = true;
    // A paused timer must not fire: the alarm would lie.
    unawaited(ReminderService.instance.cancelFocusTimerNotification());
    unawaited(AmbientSound.sync(playing: false));
    notifyListeners();
  }

  void resume() {
    if (!active || !paused) return;
    paused = false;
    _tick();
    unawaited(ReminderService.instance.scheduleFocusTimerNotification(
      duration: remaining,
      label: task?.title ?? 'Free Deep Work',
    ));
    unawaited(AmbientSound.sync(playing: true));
    notifyListeners();
  }

  /// Nudge the live countdown (timer-screen − / +). Keeps pause state;
  /// clamps at 1 min minimum and 8 h maximum.
  void adjustTime(Duration delta) {
    if (!active) return;
    final next = remaining + delta;
    remaining = next < const Duration(minutes: 1)
        ? const Duration(minutes: 1)
        : (next > const Duration(hours: 8)
            ? const Duration(hours: 8)
            : next);
    if (!paused) {
      _tick();
      // Keep the alarm honest with the new deadline.
      unawaited(ReminderService.instance.scheduleFocusTimerNotification(
        duration: remaining,
        label: task?.title ?? 'Free Deep Work',
      ));
    }
    notifyListeners();
  }

  int _elapsedMinutes() {
    final elapsed =
        plannedMinutes * 60 - remaining.inSeconds;
    return elapsed.clamp(0, 480) ~/ 60;
  }

  Future<void> finish() async {
    final id = sessionId;
    if (id == null) return;
    _ticker?.cancel();
    // Session over (early or on time): any pending alarm is now stale.
    unawaited(ReminderService.instance.cancelFocusTimerNotification());
    unawaited(AmbientSound.sync(playing: false));
    final actual = _elapsedMinutes();
    final wasFocus = mode == 'focus';
    final title = task?.title ?? 'Free Focus';
    final sub = subtaskTitle;
    _clear();
    // Chime + haptics the moment a session completes — natural expiry
    // and manual Finish both land here. Abandon stays silent on purpose.
    unawaited(SessionSound.chime());
    if (wasFocus) {
      // The garden's core loop: a finished focus session counts as the
      // first-week arc's "focus" milestone and a product event.
      BloomAnalytics.focusCompleted(minutes: actual);
      unawaited(FirstWeekArc.instance.report(FirstWeekStep.focused));
    }
    try {
      await _api.finishFocus(
          id: id,
          completed: true,
          actualMinutes: actual,
          subtask: wasFocus ? sub : null);
      notice = wasFocus
          ? (sub == null
              ? 'Focused $actual min on "$title" • heatmap +1'
              : 'Focused $actual min on "$sub" • heatmap +1')
          : 'Break over — back to it.';
    } catch (e) {
      if (e is! AuthExpiredException) {
        notice = 'Could not save session: $e';
      }
    }
    notifyListeners();
  }

  Future<void> abandon() async {
    final id = sessionId;
    if (id == null) return;
    _ticker?.cancel();
    unawaited(ReminderService.instance.cancelFocusTimerNotification());
    unawaited(AmbientSound.sync(playing: false));
    final actual = _elapsedMinutes();
    _clear();
    try {
      await _api.finishFocus(
          id: id, completed: false, actualMinutes: actual);
      // Interrupted sessions still count: partial minutes already feed
      // the focus totals, so say what was banked, not what was lost.
      notice = actual > 0
          ? '$actual real minute${actual == 1 ? '' : 's'} banked — the rest can wait.'
          : 'Paused in time — nothing lost, pick it back up anytime.';
    } catch (e) {
      if (e is! AuthExpiredException) {
        notice = 'Could not save session: $e';
      }
    }
    notifyListeners();
  }

  void _clear() {
    sessionId = null;
    task = null;
    subtaskTitle = null;
    remaining = Duration.zero;
    paused = false;
  }
}
