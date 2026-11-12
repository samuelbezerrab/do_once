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

  var testNumber = 0;
  String key(String name) => '$testNumber/$name';
  setUp(() {
    testNumber++;
    SharedPreferences.setMockInitialValues({});
    Do.configure(maxConcurrent: 1);
  });

  final runners =
      <DoScope, Future<void> Function(String, FutureOr<dynamic> Function())>{
    DoScope.session: (key, action) =>
        Do.oncePerSession(key: key, function: action),
    DoScope.forever: (key, action) => Do.once(key: key, function: action),
    DoScope.daily: (key, action) => Do.oncePerDay(key: key, function: action),
  };

  for (final scope in DoScope.values) {
    test('$scope reports completion only after the action finishes', () async {
      final actionKey = key('pending');
      final gate = Completer<void>();
      final started = Completer<void>();
      var calls = 0;
      expect(await Do.hasExecuted(key: actionKey, scope: scope), false);
      final execution = runners[scope]!(actionKey, () {
        calls++;
        started.complete();
        return gate.future;
      });
      await started.future;
      expect(await Do.hasExecuted(key: actionKey, scope: scope), false);
      expect(calls, 1);
      gate.complete();
      await execution;
      expect(await Do.hasExecuted(key: actionKey, scope: scope), true);
    });

    test('$scope does not report a failed callback as completed', () async {
      final actionKey = key('failed');
      await expectLater(
          runners[scope]!(actionKey, () => throw StateError('failure')),
          throwsStateError);
      expect(await Do.hasExecuted(key: actionKey, scope: scope), false);
    });

    test('revoking $scope affects only that scope', () async {
      final actionKey = key('revoked');
      for (final s in DoScope.values) {
        await runners[s]!(actionKey, () {});
      }
      await Do.revoke(key: actionKey, scope: scope);
      for (final s in DoScope.values) {
        expect(await Do.hasExecuted(key: actionKey, scope: s), s != scope);
      }
      var reran = false;
      await runners[scope]!(actionKey, () => reran = true);
      expect(reran, true);
    });

    test('revoking $scope does not wait for a running action', () async {
      final actionKey = key('running');
      final gate = Completer<void>();
      final started = Completer<void>();
      final execution = runners[scope]!(actionKey, () {
        started.complete();
        return gate.future;
      });
      await started.future;
      await Do.revoke(key: actionKey, scope: scope);
      expect(await Do.hasExecuted(key: actionKey, scope: scope), false);
      gate.complete();
      await execution;
      expect(await Do.hasExecuted(key: actionKey, scope: scope), true);
    });
  }

  for (final scope in [DoScope.forever, DoScope.daily]) {
    test('$scope remains incomplete while marker persistence is pending',
        () async {
      final store = PendingStore();
      SharedPreferencesStorePlatform.instance = store;
      final actionKey = key('pending-write');
      final execution = runners[scope]!(actionKey, () {});
      await store.started.future;
      expect(await Do.hasExecuted(key: actionKey, scope: scope), false);
      store.finish.complete();
      await execution;
      expect(await Do.hasExecuted(key: actionKey, scope: scope), true);
    });

    test('$scope ignores the cached marker after a failed write', () async {
      SharedPreferencesStorePlatform.instance = FailingStore();
      final actionKey = key('write-failure');
      await expectLater(runners[scope]!(actionKey, () {}), throwsStateError);
      expect(await Do.hasExecuted(key: actionKey, scope: scope), false);
    });
  }

  test('daily query and revocation affect only the current local day',
      () async {
    final actionKey = key('daily');
    final firstDay = Clock.fixed(DateTime(2024, 1, 1, 23, 59));
    final nextDay = Clock.fixed(DateTime(2024, 1, 2));
    await withClock(
        firstDay, () => Do.oncePerDay(key: actionKey, function: () {}));
    await withClock(
        nextDay, () => Do.oncePerDay(key: actionKey, function: () {}));
    await withClock(
        nextDay, () => Do.revoke(key: actionKey, scope: DoScope.daily));
    expect(
        await withClock(firstDay,
            () => Do.hasExecuted(key: actionKey, scope: DoScope.daily)),
        true);
    expect(
        await withClock(nextDay,
            () => Do.hasExecuted(key: actionKey, scope: DoScope.daily)),
        false);
  });
}
