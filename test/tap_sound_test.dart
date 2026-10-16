import 'package:daily_bloom/data/tap_sound.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  // TapSound holds static state with a _loaded guard, so the very first
  // interaction in this file must be the "defaults ON" check — later
  // loads are deliberate no-ops (asserted in the final test).
  test('first run defaults ON and tap() never throws headless', () async {
    await TapSound.load();
    expect(TapSound.enabled, isTrue);
    // Headless: no real audio platform — errors are swallowed by design.
    await TapSound.tap();
    await TapSound.stop();
  });

  test('setEnabled persists the toggle and tap() respects it', () async {
    await TapSound.setEnabled(false);
    expect(TapSound.enabled, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('bloom_tap_sound_v1'), isFalse);
    // Disabled: immediate no-op — must not touch the player at all.
    await TapSound.tap();

    await TapSound.setEnabled(true);
    expect(TapSound.enabled, isTrue);
    expect(prefs.getBool('bloom_tap_sound_v1'), isTrue);
    // Enabled but headless: player errors are swallowed, no throw.
    await TapSound.tap();
  });

  test('load() is idempotent — later loads never clobber the live toggle',
      () async {
    await TapSound.setEnabled(false);
    // A second load must not reset the in-memory value back to the
    // (empty) prefs default of ON.
    await TapSound.load();
    expect(TapSound.enabled, isFalse);
    await TapSound.setEnabled(true);
  });
}
