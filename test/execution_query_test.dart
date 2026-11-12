import 'dart:async';

import 'package:clock/clock.dart';
import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingStore extends InMemorySharedPreferencesStore {
  FailingStore() : super.empty();

  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}

class PendingStore extends InMemorySharedPreferencesStore {
  PendingStore() : super.empty();
  final started = Completer<void>();
  final finish = Completer<void>();

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    started.complete();
    await finish.future;
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a session action is reported after it completes', () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    await Execution.instance.dispose();
    await Execution.instance.initialize();

    expect(
        Execution.instance
            .hasExecuted(key: 'action', scope: ExecutionScope.session),
        false);
    await Execution.instance.doOnceOnSession(key: 'action', function: () {});
    expect(
        Execution.instance
            .hasExecuted(key: 'action', scope: ExecutionScope.session),
        true);
  });

  test('a permanent action is reported independently of the session', () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    await Execution.instance.dispose();
    await Execution.instance.initialize();

    expect(
        Execution.instance
            .hasExecuted(key: 'permanent', scope: ExecutionScope.forever),
        false);
    await Execution.instance.doOnceForever(key: 'permanent', function: () {});
    expect(
        Execution.instance
            .hasExecuted(key: 'permanent', scope: ExecutionScope.forever),
        true);
    expect(
        Execution.instance
            .hasExecuted(key: 'permanent', scope: ExecutionScope.session),
        false);
  });

  test('daily completion is reported only for the current local day', () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    await Execution.instance.dispose();
    await Execution.instance.initialize();
    final day = Clock.fixed(DateTime(2024, 1, 1, 23, 59));
    final nextDay = Clock.fixed(DateTime(2024, 1, 2));

    expect(
        withClock(
            day,
            () => Execution.instance
                .hasExecuted(key: 'daily', scope: ExecutionScope.daily)),
        false);
    await withClock(
        day, () => Execution.instance.doDaily(key: 'daily', function: () {}));
    expect(
        withClock(
            day,
            () => Execution.instance
                .hasExecuted(key: 'daily', scope: ExecutionScope.daily)),
        true);
    expect(
        withClock(
            nextDay,
            () => Execution.instance
                .hasExecuted(key: 'daily', scope: ExecutionScope.daily)),
        false);
  });

  final runners = <ExecutionScope,
      Future<void> Function(String, FutureOr<dynamic> Function())>{
    ExecutionScope.session: (key, action) =>
        Execution.instance.doOnceOnSession(key: key, function: action),
    ExecutionScope.forever: (key, action) =>
        Execution.instance.doOnceForever(key: key, function: action),
    ExecutionScope.daily: (key, action) =>
        Execution.instance.doDaily(key: key, function: action),
  };

  for (final scope in ExecutionScope.values) {
    test('$scope query observes a pending action without executing it again',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Execution.instance.initialize();
      await Execution.instance.dispose();
      await Execution.instance.initialize();
      final gate = Completer<void>();
      var calls = 0;
      final execution = runners[scope]!('pending-$scope', () {
        calls++;
        return gate.future;
      });
      expect(
          Execution.instance.hasExecuted(key: 'pending-$scope', scope: scope),
          false);
      expect(
          Execution.instance.hasExecuted(key: 'pending-$scope', scope: scope),
          false);
      expect(calls, 1);
      gate.complete();
      await execution;
      expect(
          Execution.instance.hasExecuted(key: 'pending-$scope', scope: scope),
          true);
      expect(calls, 1);
    });

    test('$scope failed callbacks are not reported as completed', () async {
      SharedPreferences.setMockInitialValues({});
      await Execution.instance.initialize();
      await Execution.instance.dispose();
      await Execution.instance.initialize();
      await expectLater(
          runners[scope]!('failed-$scope', () => throw StateError('failure')),
          throwsStateError);
      expect(Execution.instance.hasExecuted(key: 'failed-$scope', scope: scope),
          false);
    });
  }

  for (final scope in [ExecutionScope.forever, ExecutionScope.daily]) {
    test('$scope remains incomplete while marker persistence is pending',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = PendingStore();
      SharedPreferencesStorePlatform.instance = store;
      await Execution.instance.initialize();
      final key = 'pending-write-$scope';
      final execution = runners[scope]!(key, () {});
      await store.started.future;
      expect(Execution.instance.hasExecuted(key: key, scope: scope), false);
      store.finish.complete();
      await execution;
      expect(Execution.instance.hasExecuted(key: key, scope: scope), true);
    });

    test('$scope ignores the cached marker when persistence fails', () async {
      SharedPreferences.setMockInitialValues({});
      SharedPreferencesStorePlatform.instance = FailingStore();
      await Execution.instance.initialize();
      final key = 'write-failure-$scope';
      await expectLater(runners[scope]!(key, () {}), throwsStateError);
      expect(Execution.instance.hasExecuted(key: key, scope: scope), false);
    });
  }

  test('revocation clears session and permanent but not daily completion',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    await Execution.instance.dispose();
    await Execution.instance.initialize();
    for (final scope in ExecutionScope.values) {
      await runners[scope]!('revoked', () {});
      expect(
          Execution.instance.hasExecuted(key: 'revoked', scope: scope), true);
    }
    await Execution.instance.revokeKey('revoked');
    expect(
        Execution.instance
            .hasExecuted(key: 'revoked', scope: ExecutionScope.session),
        false);
    expect(
        Execution.instance
            .hasExecuted(key: 'revoked', scope: ExecutionScope.forever),
        false);
    expect(
        Execution.instance
            .hasExecuted(key: 'revoked', scope: ExecutionScope.daily),
        true);
  });
}
