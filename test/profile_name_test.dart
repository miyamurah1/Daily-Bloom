import 'package:daily_bloom/data/profile_name.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  group('greeting copy', () {
    final base = DateTime(2026, 10, 16);

    test('bands the day into morning / afternoon / evening', () {
      expect(ProfileName.greeting('', base.add(const Duration(hours: 6))),
          'Good morning');
      expect(ProfileName.greeting('', base.add(const Duration(hours: 12))),
          'Good afternoon');
      expect(ProfileName.greeting('', base.add(const Duration(hours: 18))),
          'Good evening');
    });

    test('appends the name and trims it', () {
      expect(
          ProfileName.greeting('  Maya ', base.add(const Duration(hours: 9))),
          'Good morning, Maya');
    });
  });

  test('write/read round-trips and survives a missing value', () async {
    expect(await ProfileName.read(), isEmpty);
    await ProfileName.write('  Maya  ');
    expect(await ProfileName.read(), 'Maya');
  });
}
