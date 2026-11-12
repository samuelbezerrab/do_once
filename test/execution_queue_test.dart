import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_execution/flutter_execution.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailFirstWrite extends InMemorySharedPreferencesStore {
  _FailFirstWrite() : super.empty();
  bool fail = true;

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (fail) {
      fail = false;
      return false;
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('actions start in FIFO order with one slot by default', () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    final gate = Completer<void>();
    final started = <String>[];
    final first = Execution.instance.doOnceOnSession(
        key: 'first',
        function: () {
          started.add('first');
          return gate.future;
        });
    final second = Execution.instance.doOnceOnSession(
        key: 'second',
        function: () {
          started.add('second');
        });
    await Future<void>.delayed(Duration.zero);
    expect(started, ['first']);
    gate.complete();
    await Future.wait([first, second]);
    expect(started, ['first', 'second']);
    await Execution.instance.dispose();
  });

  for (final fail in [false, true]) {
    test(
        'promotion uses the original callback and shares ${fail ? 'errors' : 'success'}',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Execution.instance.initialize();
      final gate = Completer<void>();
      final active = Completer<void>();
      final error = StateError('promoted');
      var original = 0;
      var replacement = 0;
      final blocker = Execution.instance
          .doOnceOnSession(key: 'blocker', function: () => gate.future);
      final pending = Execution.instance.doOnceOnSession(
          key: 'item',
          function: () async {
            original++;
            await active.future;
            if (fail) throw error;
          });
      final promoted = Execution.instance.doOnceOnSession(
          key: 'item',
          bypassQueue: true,
          function: () {
            replacement++;
          });
      final checks = fail
          ? [
              expectLater(pending, throwsA(same(error))),
              expectLater(promoted, throwsA(same(error)))
            ]
          : [expectLater(pending, completes), expectLater(promoted, completes)];
      expect(original, 1);
      expect(replacement, 0);
      active.complete();
      await Future.wait(checks);
      gate.complete();
      await blocker;
      await Execution.instance.dispose();
      expect(original, 1);
    });
  }

  test('parallel limit and bypass do not share slots', () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize(maxConcurrent: 2);
    final gate = Completer<void>();
    final started = <String>[];
    Future<void> run(String key, {bool bypass = false}) =>
        Execution.instance.doOnceOnSession(
            key: key,
            bypassQueue: bypass,
            function: () {
              started.add(key);
              return gate.future;
            });
    final first = run('a');
    final second = run('b');
    final third = run('c');
    final immediate = run('d', bypass: true);
    expect(started, ['a', 'b', 'd']);
    gate.complete();
    await Future.wait([first, second, third, immediate]);
    expect(started, ['a', 'b', 'd', 'c']);
    await Execution.instance.dispose();
  });

  test('invalid concurrency is rejected', () async {
    await expectLater(
        Execution.instance.initialize(maxConcurrent: 0), throwsArgumentError);
    await expectLater(
        Execution.instance.initialize(maxConcurrent: -1), throwsArgumentError);
  });

  test(
      'dispose drains queued and bypass actions, rejects new ones, and handles errors',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    final gate = Completer<void>();
    final immediateGate = Completer<void>();
    final first = Execution.instance
        .doOnceOnSession(key: 'a', function: () => gate.future);
    final second = Execution.instance
        .doOnceOnSession(key: 'b', function: () => throw StateError('failure'));
    final secondCheck = expectLater(second, throwsStateError);
    final immediate = Execution.instance.doOnceOnSession(
        key: 'c', bypassQueue: true, function: () => immediateGate.future);
    var disposed = false;
    final disposal = Execution.instance.dispose().then((_) {
      disposed = true;
    });
    await expectLater(
        Execution.instance.doOnceOnSession(key: 'd', function: () {}),
        throwsStateError);
    gate.complete();
    await first;
    await secondCheck;
    expect(disposed, false);
    immediateGate.complete();
    await immediate;
    await disposal;
    expect(disposed, true);
  });

  for (final fail in [false, true]) {
    test(
        'promoted next day waits without blocking the earlier pending day after ${fail ? 'failure' : 'success'}',
        () async {
      SharedPreferences.setMockInitialValues({});
      await Execution.instance.initialize();
      final gate = Completer<void>();
      final order = <String>[];
      final blocker = Execution.instance
          .doOnceOnSession(key: 'block', function: () => gate.future);
      final old = withClock(
          Clock.fixed(DateTime(2024, 1, 1, 23, 59)),
          () => Execution.instance.doDaily(
              key: 'daily',
              function: () {
                order.add('old');
                if (fail) throw StateError('old');
              }));
      final oldCheck = fail
          ? expectLater(old, throwsStateError)
          : expectLater(old, completes);
      final next = withClock(
          Clock.fixed(DateTime(2024, 1, 2)),
          () => Execution.instance.doDaily(
              key: 'daily',
              function: () {
                order.add('next');
              }));
      final promoted = withClock(
          Clock.fixed(DateTime(2024, 1, 2)),
          () => Execution.instance.doDaily(
              key: 'daily',
              bypassQueue: true,
              function: () {
                order.add('wrong');
              }));
      expect(order, isEmpty);
      gate.complete();
      await Future.wait([blocker, oldCheck, next, promoted]);
      expect(order, ['old', 'next']);
      await Execution.instance.dispose();
    });
  }

  test('bypass does not rerun a completed action', () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    var calls = 0;
    await Execution.instance.doOnceOnSession(
        key: 'done',
        function: () {
          calls++;
        });
    await Execution.instance.doOnceOnSession(
        key: 'done',
        bypassQueue: true,
        function: () {
          calls++;
        });
    expect(calls, 1);
    await Execution.instance.dispose();
  });

  test('concurrency cannot change while initialized', () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    await expectLater(
        Execution.instance.initialize(maxConcurrent: 2), throwsStateError);
    await Execution.instance.dispose();
  });

  test('bypass joins an already running attempt using its original callback',
      () async {
    SharedPreferences.setMockInitialValues({});
    await Execution.instance.initialize();
    final gate = Completer<void>();
    final error = StateError('running failed');
    var calls = 0;
    final first = Execution.instance.doOnceOnSession(
        key: 'running',
        function: () async {
          calls++;
          await gate.future;
          throw error;
        });
    final second = Execution.instance.doOnceOnSession(
        key: 'running',
        bypassQueue: true,
        function: () {
          calls += 100;
        });
    final checks = [
      expectLater(first, throwsA(same(error))),
      expectLater(second, throwsA(same(error)))
    ];
    await Execution.instance.initialize();
    gate.complete();
    await Future.wait(checks);
    expect(calls, 1);
    await Execution.instance.dispose();
  });

  test('a failed marker write does not stop the queue and can be retried',
      () async {
    SharedPreferences.setMockInitialValues({});
    SharedPreferencesStorePlatform.instance = _FailFirstWrite();
    await Execution.instance.initialize();
    final gate = Completer<void>();
    final first = Execution.instance
        .doOnceForever(key: 'failing', function: () => gate.future);
    final failure = expectLater(first, throwsStateError);
    var otherRan = false;
    final other = Execution.instance.doOnceOnSession(
        key: 'other',
        function: () {
          otherRan = true;
        });
    gate.complete();
    await Future.wait([failure, other]);
    expect(otherRan, true);
    var retried = false;
    await Execution.instance.doOnceForever(
        key: 'failing',
        function: () {
          retried = true;
        });
    expect(retried, true);
    await Execution.instance.dispose();
  });
}
