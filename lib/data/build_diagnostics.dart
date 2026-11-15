import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// TEMPORARY DIAGNOSTICS: what the installed build actually declares, so the
/// package id and signing-certificate SHA-1 can be compared with the Android
/// OAuth client in Firebase without adb. Remove once sign-in works.
class BuildDiagnostics {
  static const _channel = MethodChannel('com.dailybloom.app/diagnostics');

  /// Set when `Firebase.initializeApp` throws in `main()`; shown beside the
  /// fingerprint so a broken Firebase init is also visible on the device.
  static String? firebaseInitError;

  /// Human-readable block for the login screen (and the log).
  static Future<String> describe() async {
    var packageName = 'unknown';
    var sha1 = 'unavailable';
    try {
      final info =
          await _channel.invokeMapMethod<String, String>('signingInfo');
      packageName = info?['packageName'] ?? packageName;
      sha1 = info?['sha1'] ?? sha1;
    } on MissingPluginException {
      // iOS/desktop — the channel only exists on Android.
    } catch (e) {
      debugPrint('[diag] signing info failed: ${e.runtimeType}: $e');
    }
    final init = firebaseInitError;
    final text = 'pkg $packageName\nSHA-1 $sha1'
        '${init == null ? '' : '\nfirebase init: $init'}';
    debugPrint('[diag] $text');
    return text;
  }
}
