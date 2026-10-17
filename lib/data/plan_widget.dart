import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

/// Home-screen widget bridge: "Today's plan" top-3 on the launcher.
///
/// - Android renders the classic `PlanWidgetProvider` RemoteViews;
/// - iOS renders the WidgetKit `PlanWidget` extension.
/// Both read the same keys below through the shared [kPlanWidgetGroupId]
/// defaults. Taps deliver `dailybloom://` URIs back to the app (cold
/// start via [initialLaunchUri], warm via [HomeWidget.widgetClicked]);
/// [parsePlanWidgetUri] turns them into navigation intents.
///
/// Off Android/iOS (web, desktop, tests) every call degrades to a
/// no-op `false` — the widget simply never appears there.
class PlanWidgetBridge {
  /// iOS App Group shared by Runner + the widget extension. Android
  /// ignores it (plugin-private prefs). Must match both entitlements
  /// and `PlanWidget.swift`.
  static const kPlanWidgetGroupId = 'group.com.dailybloom.app.plan';

  /// Native widget names. Must match the Android receiver /
  /// `res/xml/plan_widget_info.xml` and the iOS `Widget` kind.
  static const kAndroidWidgetName = 'PlanWidgetProvider';
  static const kIOSWidgetName = 'PlanWidget';

  /// Deep-link scheme for widget taps. Never leaves the device.
  static const kScheme = 'dailybloom';

  static const String planUri = '$kScheme://plan';
  static String taskUri(String id) => '$kScheme://task/$id';

  static bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// One widget row: a planned task + its reason + done state.
  /// Keep titles short — launchers ellipsize past one line.
  static Future<bool> pushPlan(
    List<({String id, String title, String reason, bool done})> rows,
  ) async {
    if (!_supported) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(kPlanWidgetGroupId);
      }
      final visible = rows.take(3).toList();
      await HomeWidget.saveWidgetData<int>('plan_count', visible.length);
      for (var i = 0; i < 3; i++) {
        final row = i < visible.length ? visible[i] : null;
        await HomeWidget.saveWidgetData<String>(
            'plan_${i}_id', row?.id ?? '');
        await HomeWidget.saveWidgetData<String>(
            'plan_${i}_title', row?.title ?? '');
        await HomeWidget.saveWidgetData<String>(
            'plan_${i}_reason', row?.reason ?? '');
        await HomeWidget.saveWidgetData<bool>(
            'plan_${i}_done', row?.done ?? false);
      }
      await HomeWidget.updateWidget(
        androidName: kAndroidWidgetName,
        iOSName: kIOSWidgetName,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Streak + progress line for under the widget header
  /// ("Day 12 · 2 done · 3 open"). Empty string hides the row.
  static String formatStats(
      {required int streak, required int done, required int open}) {
    final parts = <String>[
      if (streak > 0) 'Day $streak',
      if (done > 0 || open > 0) '$done done · $open open',
    ];
    return parts.join(' · ');
  }

  /// Push the stats line. Same keys/group as [pushPlan]; the native
  /// widget shows the row only when the string is non-empty.
  static Future<bool> pushStats(String stats) async {
    if (!_supported) return false;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(kPlanWidgetGroupId);
      }
      await HomeWidget.saveWidgetData<String>('widget_stats', stats);
      await HomeWidget.updateWidget(
        androidName: kAndroidWidgetName,
        iOSName: kIOSWidgetName,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Warm tap subscription. Returns null off Android/iOS (web,
  /// desktop, tests) where the `home_widget/updates` channel does not
  /// exist — subscribing unguarded throws MissingPluginException during
  /// stream activation, which `onError` cannot catch.
  static StreamSubscription<Uri?>? listenWidgetClicks(
    void Function(Uri?) onData,
  ) {
    if (!_supported) return null;
    try {
      return HomeWidget.widgetClicked.listen(onData, onError: (_) {});
    } catch (_) {
      return null;
    }
  }

  /// URI the app was cold-started with via a widget tap, if any.
  static Future<Uri?> initialLaunchUri() async {
    if (!_supported) return null;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  /// Named row the app last pushed to the widget. Home registers its
  /// plan here once (type-safe, one record per task) so every screen
  /// that completes a task can refresh the widget's ✓ flags.
  static ({String id, String title, String reason})? _lastPlanRow;

  static final ValueNotifier<int> _doneRevision = ValueNotifier<int>(0);

  /// Widget source of truth for done state: the repository's done set,
  /// refreshed by AppShell when tasks change.
  static Set<String> _doneIds = {};

  /// Remember the last pushed plan so other screens can refresh it.
  static void rememberPlan(
      List<({String id, String title, String reason})> rows) {
    if (rows.isEmpty) return;
    _lastPlanRow = rows.first;
  }

  /// Re-push the remembered plan with fresh ✓ flags. Safe from any
  /// screen: no-ops when no plan was pushed yet or off mobile.
  static Future<void> refreshDoneFlags() async {
    final row = _lastPlanRow;
    if (row == null) return;
    _doneRevision.value++;
    await pushPlan([
      (id: row.id, title: row.title, reason: row.reason,
       done: _doneIds.contains(row.id)),
    ]);
  }

  /// Called by the shell when task statuses change (any screen).
  static void noteDoneIds(Set<String> doneIds) {
    if (_doneIds.length == doneIds.length &&
        _doneIds.containsAll(doneIds)) {
      return;
    }
    _doneIds = doneIds;
    refreshDoneFlags();
  }

  /// `dailybloom://task/<id>` or `dailybloom://plan`, else null.
  /// Pure function — unit-tested, no platform calls.
  static ({String type, String? id})? parsePlanWidgetUri(Uri? uri) {
    if (uri == null || uri.scheme != kScheme) return null;
    if (uri.host == 'task' && uri.pathSegments.isNotEmpty) {
      return (type: 'task', id: uri.pathSegments.first);
    }
    if (uri.host == 'plan') return (type: 'plan', id: null);
    return null;
  }
}
