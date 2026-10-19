import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';

/// Product analytics — the instrument that turns "we hope this helps"
/// into "we know this helps".
///
/// Design rules, matching the app's other static services (TapSound,
/// AmbientSound):
/// - Never throws: every call is best-effort and swallowed on failure.
/// - Auto-disabled when Firebase isn't initialized (unit tests, CI,
///   offline cold start) — [Firebase.apps] is a synchronous Dart-side
///   check, no platform channels involved.
/// - Zero PII by contract: only counts, booleans and durations. Task
///   titles, emails and usernames must never be passed here.
///
/// The five north-star questions these events answer:
/// 1. Activation — sign_up → task_created(is_first) → focus_completed
/// 2. Retention  — first_open / session via the analytics observer
/// 3. Engagement — task_completed volume per user
/// 4. Differentiator — focus_started / focus_completed minutes
/// 5. Habit loop — habit_checkin weekly rate
class BloomAnalytics {
  BloomAnalytics._();

  /// Set false in tests that exercise code paths firing events.
  static bool enabled = true;

  static bool get _ready => enabled && Firebase.apps.isNotEmpty;

  static Future<void> _log(String name, {Map<String, Object>? params}) async {
    if (!_ready) return;
    try {
      await FirebaseAnalytics.instance
          .logEvent(name: name, parameters: params);
    } catch (_) {
      // Analytics must never break the product.
    }
  }

  // --- Auth (acquisition + return) ---

  static Future<void> signUp({required String method}) =>
      _log('sign_up', params: {'method': method});

  static Future<void> login({required String method}) =>
      _log('login', params: {'method': method});

  // --- Core loop (activation + engagement) ---

  /// [isFirst] marks the account's very first task — the activation
  /// checkpoint. No title, no content: counts only.
  static Future<void> taskCreated({required bool isFirst}) =>
      _log('task_created', params: {'is_first': isFirst ? 1 : 0});

  static Future<void> taskCompleted() => _log('task_completed');

  // --- Focus (the differentiator) ---

  static Future<void> focusStarted({required int minutes}) =>
      _log('focus_started', params: {'planned_minutes': minutes});

  static Future<void> focusCompleted({required int minutes}) =>
      _log('focus_completed', params: {'actual_minutes': minutes});

  // --- Habits (weekly loop) ---

  static Future<void> habitCheckin() => _log('habit_checkin');

  // --- Features ---

  static Future<void> planMyDay() => _log('plan_my_day');
}

/// Coarse screen views from the root navigator. Forward-only: nothing
/// happens before Firebase initializes (unit tests, CI), so widget
/// tests pumping DailyBloomApp never touch a platform channel.
/// Screen names come from the route's widget type (e.g. FocusTimerScreen).
class BloomRouteObserver extends NavigatorObserver {
  void _screen(Route<dynamic>? route) {
    if (!BloomAnalytics._ready) return;
    final widget = route?.settings.name;
    final name = widget ?? route.runtimeType.toString();
    if (name.isEmpty) return;
    FirebaseAnalytics.instance
        .logScreenView(screenName: name, screenClass: name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _screen(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _screen(newRoute);
}