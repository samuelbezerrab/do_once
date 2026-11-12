import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:do_once/do_once.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

typedef Run = Future<void> Function(
    String key, FutureOr<dynamic> Function() action);

class FailingStore extends InMemorySharedPreferencesStore {
  FailingStore(this.throws) : super.empty();
  final bool throws;
  int writes = 0;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (writes == 1) {
      if (throws) throw StateError('write failed');
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    await Execution.instance.dispose();
    await Execution.instance.initialize();
  });

  test('overlapping session calls share one execution', () async {
    final gate = Completer<void>();
    var calls = 0;
    Future<void> action() async {
      calls++;
      await gate.future;
    }

    final first =
        Execution.instance.doOnceOnSession(key: 'key', function: action);
    final second =
        Execution.instance.doOnceOnSession(key: 'key', function: action);
    expect(calls, 1);
    gate.complete();
    await Future.wait([first, second]);
    expect(calls, 1);
  });

  final runners = <String, Run>{
    'session': (key, action) =>
        Execution.instance.doOnceOnSession(key: key, function: action),
    'forever': (key, action) =>
        Execution.instance.doOnceForever(key: key, function: action),
    'daily': (key, action) =>
        Execution.instance.doDaily(key: key, function: action),
  };
  runners.forEach((scope, run) {
    test('$scope shares a directly thrown callback error', () async {
      final error = StateError('synchronous callback failure');
      var calls = 0;
      dynamic action() {
        calls++;
        throw error;
      }

      final first = run('direct-sync', action);
      final second = run('direct-sync', action);
      await Future.wait([
        expectLater(first, throwsA(same(error))),
        expectLater(second, throwsA(same(error))),
      ]);
      expect(calls, 1);
      await run('direct-sync', () {
        calls++;
      });
      expect(calls, 2);
    });
    test('$scope shares an overlapping success', () async {
      final gate = Completer<void>();
      var calls = 0;
      Future<void> action() async {
        calls++;
        await gate.future;
      }

      final first = run('success', action);
      final second = run('success', action);
      expect(calls, 1);
      gate.complete();
      await Future.wait([first, second]);
      await run('success', action);
      expect(calls, 1);
    });
    for (final synchronous in [true, false]) {
      test(
          '$scope shares ${synchronous ? 'sync' : 'async'} errors and permits retry',
          () async {
        final gate = Completer<void>();
        final error = StateError('callback failed');
        var calls = 0;
        FutureOr<dynamic> action() {
          calls++;
          if (synchronous) throw error;
          return gate.future;
        }

        // Keep the first attempt pending so both callers join it, then throw.
        final blocker = Completer<void>();
        Future<void> delayed() async {
          await blocker.future;
          await action();
        }

        final first = run('error', delayed);
        final second = run('error', delayed);
        final firstCheck = expectLater(first, throwsA(same(error)));
        final secondCheck = expectLater(second, throwsA(same(error)));
        blocker.complete();
        if (!synchronous) {
          await Future<void>.delayed(Duration.zero);
          gate.completeError(error);
        }
        await Future.wait([firstCheck, secondCheck]);
        expect(calls, 1);
        await run('error', () {
          calls++;
        });
        expect(calls, 2);
      });
    }
  });

  for (final scope in ['forever', 'daily']) {
    for (final throws in [false, true]) {
      test(
          '$scope propagates ${throws ? 'thrown' : 'false'} write failure and retries',
          () async {
        final store = FailingStore(throws);
        SharedPreferencesStorePlatform.instance = store;
        final gate = Completer<void>();
        var calls = 0;
        Future<void> action() async {
          calls++;
          await gate.future;
        }

        final first = runners[scope]!('write-$scope-$throws', action);
        final second = runners[scope]!('write-$scope-$throws', action);
        final checks = [
          expectLater(first, throwsA(anything)),
          expectLater(second, throwsA(anything))
        ];
        gate.complete();
        await Future.wait(checks);
        expect(calls, 1);
        expect(store.writes, 1);
        await runners[scope]!('write-$scope-$throws', () {
          calls++;
        });
        expect(calls, 2);
        expect(store.writes, 2);
      });
    }
  }

  test('formerly colliding dates are distinct and ignore legacy markers',
      () async {
    SharedPreferences.setMockInitialValues(
        {'A2S-Execution_1112024_date': true});
    await Execution.instance.initialize();
    var calls = 0;
    Future<void> run(DateTime date) => withClock(
        Clock.fixed(date),
        () => Execution.instance.doDaily(
            key: 'date',
            function: () {
              calls++;
            }));
    await run(DateTime(2024, 1, 11));
    await run(DateTime(2024, 11, 1));
    await run(DateTime(2024, 1, 11));
    expect(calls, 2);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('A2S-Execution_1112024_date'), true);
  });

  for (final fails in [false, true]) {
    test(
        'daily serializes different days after ${fails ? 'failure' : 'success'}',
        () async {
      final oldGate = Completer<void>();
      final newGate = Completer<void>();
      var active = 0;
      var oldCalls = 0;
      var newCalls = 0;
      final error = StateError('old day failed');
      final first = withClock(
          Clock.fixed(DateTime(2024, 1, 1, 23, 59)),
          () => Execution.instance.doDaily(
              key: 'midnight',
              function: () async {
                oldCalls++;
                active++;
                await oldGate.future;
                active--;
                if (fails) throw error;
              }));
      final firstCheck = fails
          ? expectLater(first, throwsA(same(error)))
          : expectLater(first, completes);
      Future<void> next() => withClock(
          Clock.fixed(DateTime(2024, 1, 2)),
          () => Execution.instance.doDaily(
              key: 'midnight',
              function: () async {
                expect(active, 0);
                active++;
                newCalls++;
                await newGate.future;
                active--;
              }));
      final second = next();
      final third = next();
      expect(oldCalls, 1);
      expect(newCalls, 0);
      oldGate.complete();
      await firstCheck;
      await Future<void>.delayed(Duration.zero);
      expect(newCalls, 1);
      newGate.complete();
      await Future.wait([second, third]);
      expect(newCalls, 1);
    });
  }

  test('independent keys and scopes proceed while another execution waits',
      () async {
    final gate = Completer<void>();
    final first = Execution.instance
        .doOnceOnSession(key: 'same', function: () => gate.future);
    var calls = 0;
    await Execution.instance.doOnceOnSession(
        key: 'other',
        bypassQueue: true,
        function: () {
          calls++;
        });
    await Execution.instance.doOnceForever(
        key: 'same',
        bypassQueue: true,
        function: () {
          calls++;
        });
    await Execution.instance.doDaily(
        key: 'same',
        bypassQueue: true,
        function: () {
          calls++;
        });
    expect(calls, 3);
    gate.complete();
    await first;
  });

  test('daily and permanent markers cannot collide across keys', () async {
    var calls = 0;
    await withClock(
        Clock.fixed(DateTime(2024, 1, 1)),
        () => Execution.instance.doDaily(
            key: 'item',
            function: () {
              calls++;
            }));
    await Execution.instance.doOnceForever(
        key: 'daily-v2_2024-01-01_item',
        function: () {
          calls++;
        });
    expect(calls, 2);
  });
}
