import 'package:daily_bloom/data/auth_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: Google sign-in on Android only mints a Firebase-compatible
/// ID token when `GoogleSignIn` gets an explicit `serverClientId` — the
/// plugin's fallback resource (R.string.default_web_client_id) does not
/// exist in this project (no google-services.json, no Gradle plugin), and
/// without it every sign-in fails and nothing persists to remember.
void main() {
  test('Google sign-in uses the real web client ID audience', () {
    expect(AuthStore.googleWebClientId, isNotEmpty);
    expect(AuthStore.googleWebClientId,
        endsWith('.apps.googleusercontent.com'));
    expect(AuthStore.googleWebClientId, isNot(contains('CI-STUB')));
  });
}
