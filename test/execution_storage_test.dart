import 'package:clock/clock.dart';
import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persistent markers use separate keys and preserve app preferences',
      () async {
    SharedPreferences.setMockInitialValues({'other.setting': true});
    await Do.once(key: 'setup', function: () {});
    await withClock(Clock.fixed(DateTime(2024, 1, 2)),
        () => Do.oncePerDay(key: 'setup', function: () {}));
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(preferences.getBool('do_once_forever_setup'), true);
    expect(preferences.getBool('do_once_daily_v2_2024-01-02_setup'), true);
    expect(preferences.getBool('other.setting'), true);
    await Do.revoke(key: 'setup', scope: DoScope.forever);
    await preferences.reload();
    expect(preferences.getBool('do_once_forever_setup'), false);
    expect(preferences.getBool('do_once_daily_v2_2024-01-02_setup'), true);
    expect(preferences.getBool('other.setting'), true);
    await withClock(Clock.fixed(DateTime(2024, 1, 2)),
        () => Do.revoke(key: 'setup', scope: DoScope.daily));
    await preferences.reload();
    expect(preferences.getBool('do_once_daily_v2_2024-01-02_setup'), false);
    expect(preferences.getBool('other.setting'), true);
  });

  test('previously stored markers are read automatically', () async {
    SharedPreferences.setMockInitialValues({
      'do_once_forever_loaded': true,
      'do_once_daily_v2_2024-01-02_loaded': true,
    });
    var calls = 0;
    await Do.once(key: 'loaded', function: () => calls++);
    await withClock(Clock.fixed(DateTime(2024, 1, 2)),
        () => Do.oncePerDay(key: 'loaded', function: () => calls++));
    expect(calls, 0);
  });
}
