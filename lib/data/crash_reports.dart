import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in crash reporting (Sentry). Two gates, both must pass:
///
/// 1. A DSN baked in at build time (`--dart-define=SENTRY_DSN=...`).
///    Open-source / local builds ship with an empty DSN: fully disabled,
///    zero network, zero behavior change.
/// 2. The in-app Settings toggle (default off, persisted). Turning it off
///    stops all future reports; takes effect on next launch.
///
/// No breadcrumbs with task content: only the exception, OS, and app
/// version leave the device.
class CrashReports {
  static const _kKey = 'bloom_crash_reports_v1';

  /// Build-time DSN. Empty unless the release pipeline passes one.
  static const dsn = String.fromEnvironment('SENTRY_DSN');

  static Future<bool> enabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  static Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kKey, value);
    } catch (_) {}
  }

  /// True only when reports would actually be sent.
  static Future<bool> active() async =>
      dsn.isNotEmpty && await enabled();

  static Future<void> init(Future<void> Function() body) async {
    if (dsn.isEmpty || !await enabled()) {
      await body();
      return;
    }
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.tracesSampleRate = 0.1;
      },
      appRunner: body,
    );
  }

  /// Manual report hook for caught errors that still matter.
  static Future<void> report(Object error, [StackTrace? stack]) async {
    if (dsn.isEmpty || !await enabled()) return;
    try {
      await Sentry.captureException(error, stackTrace: stack);
    } catch (_) {}
  }
}
