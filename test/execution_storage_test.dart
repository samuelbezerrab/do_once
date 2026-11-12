import 'package:clock/clock.dart';
import 'package:flutter_execution/flutter_execution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('persistent markers use the do_once namespace for each scope', () async {
    SharedPreferences.setMockInitialValues({'other.setting': true});
    final execution = Execution.instance;
    await execution.initialize();
    await execution.doOnceForever(key: 'setup', function: () {});
    await withClock(Clock.fixed(DateTime(2024, 1, 2)),
        () => execution.doDaily(key: 'setup', function: () {}));
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(preferences.getBool('do_once_forever_setup'), true);
    expect(preferences.getBool('do_once_daily_v2_2024-01-02_setup'), true);
    expect(preferences.getBool('other.setting'), true);
    expect(preferences.getKeys(), {
      'other.setting',
      'do_once_forever_setup',
      'do_once_daily_v2_2024-01-02_setup',
    });
    await execution.revokeKey('setup');
    await preferences.reload();
    expect(preferences.getBool('do_once_forever_setup'), false);
    expect(preferences.getBool('do_once_daily_v2_2024-01-02_setup'), true);
    expect(preferences.getBool('other.setting'), true);
    await execution.dispose();
  });

  test('old markers are ignored and left untouched', () async {
    SharedPreferences.setMockInitialValues({
      'A2S-Execution_setup': true,
      'A2S-Execution-daily-v2_2024-01-02_setup': true,
    });
    final execution = Execution.instance;
    await execution.initialize();
    var runs = 0;
    expect(execution.hasExecuted(key: 'setup', scope: ExecutionScope.forever),
        false);
    await execution.doOnceForever(
        key: 'setup',
        function: () {
          runs++;
        });
    await withClock(Clock.fixed(DateTime(2024, 1, 2)), () async {
      expect(execution.hasExecuted(key: 'setup', scope: ExecutionScope.daily),
          false);
      await execution.doDaily(
          key: 'setup',
          function: () {
            runs++;
          });
    });
    expect(runs, 2);
    await execution.revokeKey('setup');
    await execution.dispose();
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(preferences.getBool('A2S-Execution_setup'), true);
    expect(
        preferences.getBool('A2S-Execution-daily-v2_2024-01-02_setup'), true);
  });
}
