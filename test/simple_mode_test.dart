import 'package:daily_bloom/data/simple_mode.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SimpleMode.instance.debugReset(false);
  });
  tearDown(() {
    SharedPreferences.setMockInitialValues({});
    SimpleMode.instance.debugReset(false);
  });

  test('defaults OFF — existing accounts keep every door', () {
    expect(SimpleMode.instance.enabled, isFalse);
  });

  test('setEnabled persists, notifies, and survives a reload', () async {
    var notified = false;
    SimpleMode.instance.addListener(() => notified = true);

    await SimpleMode.instance.setEnabled(true);
    expect(SimpleMode.instance.enabled, isTrue);
    expect(notified, isTrue);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('bloom_simple_mode_v1'), isTrue);

    // Simulate a fresh boot: load reads the persisted toggle.
    SimpleMode.instance.debugReset(false);
    await SimpleMode.instance.load();
    expect(SimpleMode.instance.enabled, isTrue);
  });
}
