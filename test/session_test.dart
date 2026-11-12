import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session completion is in memory, independent of persistent markers',
      () async {
    SharedPreferences.setMockInitialValues({'app.theme': 'dark'});
    await Do.oncePerSession(key: 'session', function: () {});
    await Do.once(key: 'session', function: () {});
    await Do.revoke(key: 'session', scope: DoScope.forever);
    expect(await Do.hasExecuted(key: 'session', scope: DoScope.session), true);
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(preferences.getString('app.theme'), 'dark');
    expect(preferences.getKeys().where((key) => key.contains('session')),
        ['do_once_forever_session']);
  });
}
