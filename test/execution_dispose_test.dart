import 'dart:async';

import 'package:clock/clock.dart';
import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dispose preserves app preferences and persistent execution markers',
      () async {
    SharedPreferences.setMockInitialValues({'app.theme': 'dark'});
    final execution = Execution.instance;
    await execution.initialize();
    await execution.doOnceOnSession(key: 'session', function: () {});
    await execution.doOnceForever(key: 'forever', function: () {});
    await withClock(Clock.fixed(DateTime(2024, 1, 1)),
        () => execution.doDaily(key: 'daily', function: () {}));

    await execution.dispose();
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    expect(preferences.getString('app.theme'), 'dark');
    await execution.initialize();
    expect(execution.hasExecuted(key: 'forever', scope: ExecutionScope.forever),
        true);
    expect(
        withClock(
            Clock.fixed(DateTime(2024, 1, 1)),
            () => execution.hasExecuted(
                key: 'daily', scope: ExecutionScope.daily)),
        true);
    expect(execution.hasExecuted(key: 'session', scope: ExecutionScope.session),
        false);
    await execution.dispose();
  });

  test('dispose preserves markers written by actions it drains', () async {
    SharedPreferences.setMockInitialValues({});
    final execution = Execution.instance;
    await execution.initialize();
    final gate = Completer<void>();
    final action =
        execution.doOnceForever(key: 'pending', function: () => gate.future);
    var disposed = false;
    final disposal = execution.dispose().then((_) {
      disposed = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(disposed, false);
    gate.complete();
    await Future.wait([action, disposal]);
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    await execution.initialize();
    expect(execution.hasExecuted(key: 'pending', scope: ExecutionScope.forever),
        true);
    await execution.dispose();
  });
}
