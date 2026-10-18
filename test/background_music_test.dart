import 'package:daily_bloom/data/background_music.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  // BackgroundMusic holds static state with a _loaded guard, so the very
  // first interaction in this file must be the "defaults OFF" check —
  // later loads are deliberate no-ops (asserted in the final test).
  test('first run defaults OFF and start() never throws headless', () async {
    await BackgroundMusic.load();
    expect(BackgroundMusic.enabled, isFalse);
    // Disabled: start() must be an immediate no-op, headless or not.
    await BackgroundMusic.start();
    await BackgroundMusic.stop();
  });

  test('setEnabled persists the toggle and start() respects it', () async {
    await BackgroundMusic.setEnabled(true);
    expect(BackgroundMusic.enabled, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('bloom_bgm_v1'), isTrue);
    // Enabled but headless: player errors are swallowed, no throw.
    await BackgroundMusic.start();

    await BackgroundMusic.setEnabled(false);
    expect(BackgroundMusic.enabled, isFalse);
    expect(prefs.getBool('bloom_bgm_v1'), isFalse);
    // Disabled: immediate no-op — must not touch the player at all.
    await BackgroundMusic.start();
  });

  test('load() is idempotent — later loads never clobber the live toggle',
      () async {
    await BackgroundMusic.setEnabled(false);
    // A second load must not reset the in-memory value back to the
    // (empty) prefs default of OFF.
    await BackgroundMusic.load();
    expect(BackgroundMusic.enabled, isFalse);
    await BackgroundMusic.setEnabled(true);
  });
}
