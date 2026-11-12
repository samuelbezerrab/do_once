import 'dart:async';

import 'package:clock/clock.dart';
import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
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

  var testNumber = 0;
  String key(String name) => '$testNumber/$name';
  setUp(() {
    testNumber++;
    SharedPreferences.setMockInitialValues({});
    Do.configure(maxConcurrent: 1);
  });

  final runners = <String, Run>{
    'session': (key, action) => Do.oncePerSession(key: key, function: action),
    'forever': (key, action) => Do.once(key: key, function: action),
    'daily': (key, action) => Do.oncePerDay(key: key, function: action),
  };

  for (final entry in runners.entries) {
    test('${entry.key} shares overlapping calls and the first function',
        () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      var firstCalls = 0;
      var otherCalls = 0;
      final first = entry.value(key('success'), () async {
        firstCalls++;
        started.complete();
        await gate.future;
      });
      final second = entry.value(key('success'), () => otherCalls++);
      await started.future;
      expect(firstCalls, 1);
      expect(otherCalls, 0);
      gate.complete();
      await Future.wait([first, second]);
      await entry.value(key('success'), () => otherCalls++);
      expect(otherCalls, 0);
    });

    test('${entry.key} shares a directly thrown synchronous error', () async {
      final error = StateError('synchronous callback failure');
      var calls = 0;
      dynamic action() {
        calls++;
        throw error;
      }

      final first = entry.value(key('direct-error'), action);
      final second = entry.value(key('direct-error'), action);
      await Future.wait([
        expectLater(first, throwsA(same(error))),
        expectLater(second, throwsA(same(error))),
      ]);
      expect(calls, 1);
      await entry.value(key('direct-error'), () => calls++);
      expect(calls, 2);
    });

    for (final synchronous in [true, false]) {
      test(
          '${entry.key} shares ${synchronous ? 'sync' : 'async'} errors and retries',
          () async {
        final gate = Completer<void>();
        final error = StateError('callback failed');
        var calls = 0;
        final first = entry.value(key('error'), () async {
          calls++;
          if (!synchronous) await gate.future;
          throw error;
        });
        final second = entry.value(key('error'), () => calls += 100);
        final checks = [
          expectLater(first, throwsA(same(error))),
          expectLater(second, throwsA(same(error))),
        ];
        if (!synchronous) gate.complete();
        await Future.wait(checks);
        expect(calls, 1);
        await entry.value(key('error'), () => calls++);
        expect(calls, 2);
      });
    }
  }

  test('onceAndDone shares the permanent marker and in-flight attempt',
      () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var calls = 0;
    final first = Do.onceAndDone(
        key: key('alias'),
        function: () async {
          calls++;
          started.complete();
          await gate.future;
        });
    final second = Do.once(key: key('alias'), function: () => calls += 100);
    await started.future;
    gate.complete();
    await Future.wait([first, second]);
    await Do.onceAndDone(key: key('alias'), function: () => calls += 100);
    expect(calls, 1);
    expect(
        await Do.hasExecuted(key: key('alias'), scope: DoScope.forever), true);
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

        final first = runners[scope]!(key('write'), action);
        final second = runners[scope]!(key('write'), action);
        final checks = [
          expectLater(first, throwsA(anything)),
          expectLater(second, throwsA(anything)),
        ];
        gate.complete();
        await Future.wait(checks);
        expect(calls, 1);
        expect(store.writes, 1);
        await runners[scope]!(key('write'), () => calls++);
        expect(calls, 2);
        expect(store.writes, 2);
      });
    }
  }

  test('distinct calendar dates have distinct markers', () async {
    var calls = 0;
    Future<void> run(DateTime date) => withClock(Clock.fixed(date),
        () => Do.oncePerDay(key: key('date'), function: () => calls++));
    await run(DateTime(2024, 1, 11));
    await run(DateTime(2024, 11, 1));
    await run(DateTime(2024, 1, 11));
    expect(calls, 2);
  });

  test('a queued daily action uses the local date at call time', () async {
    final gate = Completer<void>();
    final blocker =
        Do.oncePerSession(key: key('blocker'), function: () => gate.future);
    final day = Clock.fixed(DateTime(2024, 1, 1, 23, 59));
    final nextDay = Clock.fixed(DateTime(2024, 1, 2));
    final action = withClock(
        day, () => Do.oncePerDay(key: key('queued-day'), function: () {}));
    gate.complete();
    await Future.wait([blocker, action]);
    expect(
        await withClock(day,
            () => Do.hasExecuted(key: key('queued-day'), scope: DoScope.daily)),
        true);
    expect(
        await withClock(nextDay,
            () => Do.hasExecuted(key: key('queued-day'), scope: DoScope.daily)),
        false);
  });

  for (final fails in [false, true]) {
    test(
        'daily serializes different days after ${fails ? 'failure' : 'success'}',
        () async {
      final oldGate = Completer<void>();
      final oldStarted = Completer<void>();
      final nextStarted = Completer<void>();
      final error = StateError('old day failed');
      var active = false;
      var nextCalls = 0;
      final first = withClock(
          Clock.fixed(DateTime(2024, 1, 1, 23, 59)),
          () => Do.oncePerDay(
              key: key('midnight'),
              function: () async {
                active = true;
                oldStarted.complete();
                await oldGate.future;
                active = false;
                if (fails) throw error;
              }));
      final firstCheck = fails
          ? expectLater(first, throwsA(same(error)))
          : expectLater(first, completes);
      await oldStarted.future;
      Future<void> next() => withClock(
          Clock.fixed(DateTime(2024, 1, 2)),
          () => Do.oncePerDay(
              key: key('midnight'),
              bypassQueue: true,
              function: () {
                expect(active, false);
                nextCalls++;
                nextStarted.complete();
              }));
      final second = next();
      final third = next();
      expect(nextCalls, 0);
      oldGate.complete();
      await firstCheck;
      await nextStarted.future;
      await Future.wait([second, third]);
      expect(nextCalls, 1);
    });
  }

  test('independent keys and scopes proceed with bypass', () async {
    final gate = Completer<void>();
    final first =
        Do.oncePerSession(key: key('same'), function: () => gate.future);
    var calls = 0;
    await Do.oncePerSession(
        key: key('other'), bypassQueue: true, function: () => calls++);
    await Do.once(key: key('same'), bypassQueue: true, function: () => calls++);
    await Do.oncePerDay(
        key: key('same'), bypassQueue: true, function: () => calls++);
    expect(calls, 3);
    gate.complete();
    await first;
  });

  test('daily and permanent markers cannot collide across keys', () async {
    var calls = 0;
    await withClock(Clock.fixed(DateTime(2024, 1, 1)),
        () => Do.oncePerDay(key: 'item', function: () => calls++));
    await Do.once(key: 'daily_v2_2024-01-01_item', function: () => calls++);
    expect(calls, 2);
  });
}
