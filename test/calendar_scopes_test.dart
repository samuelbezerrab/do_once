import 'dart:async';

import 'package:clock/clock.dart';
import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Do.configure(maxConcurrent: 1);
  });

  test('hourly executes once per local calendar hour', () async {
    var calls = 0;
    Future<void> run(DateTime time) => withClock(Clock.fixed(time),
        () => Do.oncePerHour(key: 'hourly', function: () => calls++));

    await run(DateTime(2024, 12, 31, 23, 0));
    await run(DateTime(2024, 12, 31, 23, 59));
    await run(DateTime(2025, 1, 1));
    await run(DateTime(2024, 12, 31, 23, 30));

    expect(calls, 2);
  });

  final firstRepeatedHour =
      DateTime.parse('2024-11-03T01:30:00-04:00').toLocal();
  final secondRepeatedHour =
      DateTime.parse('2024-11-03T01:30:00-05:00').toLocal();
  test('a repeated local hour shares one completion marker', () async {
    var calls = 0;
    await withClock(Clock.fixed(firstRepeatedHour),
        () => Do.oncePerHour(key: 'repeated-hour', function: () => calls++));
    await withClock(Clock.fixed(secondRepeatedHour),
        () => Do.oncePerHour(key: 'repeated-hour', function: () => calls++));
    expect(calls, 1);
  },
      skip: firstRepeatedHour.hour != secondRepeatedHour.hour ||
              firstRepeatedHour.timeZoneOffset ==
                  secondRepeatedHour.timeZoneOffset
          ? 'Requires a local time zone with the 2024 New York DST transition'
          : false);

  test('monthly executes once per local calendar month', () async {
    var calls = 0;
    Future<void> run(DateTime time) => withClock(Clock.fixed(time),
        () => Do.oncePerMonth(key: 'monthly', function: () => calls++));

    await run(DateTime(2024, 12, 1));
    await run(DateTime(2024, 12, 31, 23, 59));
    await run(DateTime(2025, 1, 1));
    await run(DateTime(2024, 12, 15));

    expect(calls, 2);
  });

  test('yearly executes once per local calendar year', () async {
    var calls = 0;
    Future<void> run(DateTime time) => withClock(Clock.fixed(time),
        () => Do.oncePerYear(key: 'yearly', function: () => calls++));

    await run(DateTime(2024, 1, 1));
    await run(DateTime(2024, 12, 31, 23, 59));
    await run(DateTime(2025, 1, 1));
    await run(DateTime(2024, 6, 1));

    expect(calls, 2);
  });

  test('hourly completion can be queried and revoked for the current hour',
      () async {
    await Do.oncePerHour(key: 'query-hour', function: () {});
    expect(
        await Do.hasExecuted(key: 'query-hour', scope: DoScope.hourly), true);
    await Do.revoke(key: 'query-hour', scope: DoScope.hourly);
    expect(
        await Do.hasExecuted(key: 'query-hour', scope: DoScope.hourly), false);
  });

  test('monthly completion can be queried and revoked', () async {
    await Do.oncePerMonth(key: 'query-month', function: () {});
    expect(
        await Do.hasExecuted(key: 'query-month', scope: DoScope.monthly), true);
    await Do.revoke(key: 'query-month', scope: DoScope.monthly);
    expect(await Do.hasExecuted(key: 'query-month', scope: DoScope.monthly),
        false);
  });

  test('yearly completion can be queried and revoked', () async {
    await Do.oncePerYear(key: 'query-year', function: () {});
    expect(
        await Do.hasExecuted(key: 'query-year', scope: DoScope.yearly), true);
    await Do.revoke(key: 'query-year', scope: DoScope.yearly);
    expect(
        await Do.hasExecuted(key: 'query-year', scope: DoScope.yearly), false);
  });

  final calendarScopes = <DoScope,
      ({
    DateTime before,
    DateTime after,
    Future<void> Function(String, FutureOr<dynamic> Function()) run
  })>{
    DoScope.hourly: (
      before: DateTime(2024, 12, 31, 23, 59),
      after: DateTime(2025),
      run: (key, action) => Do.oncePerHour(key: key, function: action),
    ),
    DoScope.monthly: (
      before: DateTime(2024, 12, 31, 23, 59),
      after: DateTime(2025),
      run: (key, action) => Do.oncePerMonth(key: key, function: action),
    ),
    DoScope.yearly: (
      before: DateTime(2024, 12, 31, 23, 59),
      after: DateTime(2025),
      run: (key, action) => Do.oncePerYear(key: key, function: action),
    ),
  };

  for (final entry in calendarScopes.entries) {
    final scope = entry.key;
    final spec = entry.value;

    test('$scope uses the period at call time when queued', () async {
      final gate = Completer<void>();
      final blocker =
          Do.oncePerSession(key: 'blocker-$scope', function: () => gate.future);
      final action = withClock(
          Clock.fixed(spec.before), () => spec.run('queued-$scope', () {}));
      gate.complete();
      await Future.wait([blocker, action]);
      expect(
          await withClock(Clock.fixed(spec.before),
              () => Do.hasExecuted(key: 'queued-$scope', scope: scope)),
          true);
      expect(
          await withClock(Clock.fixed(spec.after),
              () => Do.hasExecuted(key: 'queued-$scope', scope: scope)),
          false);
    });

    test('$scope revocation affects only the current period', () async {
      const key = 'period-revoke';
      await withClock(Clock.fixed(spec.before), () => spec.run(key, () {}));
      await withClock(Clock.fixed(spec.after), () => spec.run(key, () {}));
      await withClock(
          Clock.fixed(spec.after), () => Do.revoke(key: key, scope: scope));
      expect(
          await withClock(Clock.fixed(spec.before),
              () => Do.hasExecuted(key: key, scope: scope)),
          true);
      expect(
          await withClock(Clock.fixed(spec.after),
              () => Do.hasExecuted(key: key, scope: scope)),
          false);
    });
  }
}
