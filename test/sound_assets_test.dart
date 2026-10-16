import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression: `rain.wav` shipped on disk for ages but was never listed
/// under `assets:` in pubspec.yaml, so the rain toggle loaded nothing and
/// failed silently. Every sound the app plays must be in the bundle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled sound assets load from the declared assets list', () {
    for (final asset in [
      'assets/sounds/tap.wav',
      'assets/sounds/bell.wav',
      'assets/sounds/rain.wav',
    ]) {
      test(asset, () async {
        final data = await rootBundle.load(asset);
        expect(data.lengthInBytes, greaterThan(0),
            reason: '$asset must be declared under pubspec assets:');
      });
    }
  });
}
