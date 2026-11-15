import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';
import 'auth_store.dart';

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
    // The baked values this build actually uses — the things the Firebase
    // console must match.
    final options = DefaultFirebaseOptions.currentPlatform;
    final init = firebaseInitError;
    final lines = [
      'pkg $packageName',
      'SHA-1 $sha1',
      'project ${options.projectId}',
      'appId ${options.appId}',
      'webClient ${AuthStore.googleWebClientId}',
      if (init != null) 'firebase init: $init',
    ];
    final text = lines.join('\n');
    debugPrint('[diag] $text');
    return text;
  }
}
