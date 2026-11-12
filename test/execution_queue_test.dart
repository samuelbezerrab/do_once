import 'dart:async';

import 'package:clock/clock.dart';
import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailFirstWriteStore extends InMemorySharedPreferencesStore {
  FailFirstWriteStore() : super.empty();
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

  var testNumber = 0;
  String key(String name) => '$testNumber/$name';
  setUp(() {
    testNumber++;
    SharedPreferences.setMockInitialValues({});
    Do.configure(maxConcurrent: 1);
  });

  test('actions start in FIFO order with one slot by default', () async {
    final gate = Completer<void>();
    final started = <String>[];
    final first = Do.oncePerSession(
        key: key('first'),
        function: () {
          started.add('first');
          return gate.future;
        });
    final second = Do.oncePerSession(
        key: key('second'),
        function: () {
          started.add('second');
        });
    expect(started, ['first']);
    gate.complete();
    await Future.wait([first, second]);
    expect(started, ['first', 'second']);
  });

  test('increasing the limit starts waiting actions immediately in FIFO order',
      () async {
    final gate = Completer<void>();
    final started = <String>[];
    Future<void> run(String name) => Do.oncePerSession(
        key: key(name),
        function: () {
          started.add(name);
          return gate.future;
        });
    final actions = [run('a'), run('b'), run('c'), run('d')];
    expect(started, ['a']);
    Do.configure(maxConcurrent: 3);
    expect(started, ['a', 'b', 'c']);
    gate.complete();
    await Future.wait(actions);
    expect(started, ['a', 'b', 'c', 'd']);
  });

  test('decreasing the limit does not interrupt running actions', () async {
    Do.configure(maxConcurrent: 3);
    final gates = List.generate(4, (_) => Completer<void>());
    final started = <int>[];
    Future<void> run(int i) => Do.oncePerSession(
        key: key('$i'),
        function: () {
          started.add(i);
          return gates[i].future;
        });
    final actions = [for (var i = 0; i < 4; i++) run(i)];
    expect(started, [0, 1, 2]);
    Do.configure(maxConcurrent: 1);
    gates[0].complete();
    await actions[0];
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2]);
    gates[1].complete();
    await actions[1];
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2]);
    gates[2].complete();
    await actions[2];
    await Future<void>.delayed(Duration.zero);
    expect(started, [0, 1, 2, 3]);
    gates[3].complete();
    await actions[3];
  });

  test('invalid concurrency is rejected without changing the current limit',
      () async {
    expect(() => Do.configure(maxConcurrent: 0), throwsArgumentError);
    expect(() => Do.configure(maxConcurrent: -1), throwsArgumentError);
    final gate = Completer<void>();
    var started = 0;
    final first = Do.oncePerSession(key: key('a'), function: () => gate.future);
    final second = Do.oncePerSession(key: key('b'), function: () => started++);
    expect(started, 0);
    gate.complete();
    await Future.wait([first, second]);
    expect(started, 1);
  });

  test('bypassed actions do not occupy configured slots', () async {
    Do.configure(maxConcurrent: 2);
    final gate = Completer<void>();
    final started = <String>[];
    Future<void> run(String name, {bool bypass = false}) => Do.oncePerSession(
        key: key(name),
        bypassQueue: bypass,
        function: () {
          started.add(name);
          return gate.future;
        });
    final first = run('a');
    final second = run('b');
    final third = run('c');
    final bypass = run('d', bypass: true);
    expect(started, ['a', 'b', 'd']);
    gate.complete();
    await Future.wait([first, second, third, bypass]);
    expect(started, ['a', 'b', 'd', 'c']);
  });

  for (final fails in [false, true]) {
    test(
        'promotion preserves the first function and shares ${fails ? 'errors' : 'success'}',
        () async {
      final gate = Completer<void>();
      final active = Completer<void>();
      final error = StateError('promoted');
      var original = 0;
      var replacement = 0;
      final blocker =
          Do.oncePerSession(key: key('block'), function: () => gate.future);
      final pending = Do.oncePerSession(
          key: key('item'),
          function: () async {
            original++;
            await active.future;
            if (fails) throw error;
          });
      final promoted = Do.oncePerSession(
          key: key('item'), bypassQueue: true, function: () => replacement++);
      final checks = fails
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
      await Future<void>.delayed(Duration.zero);
      expect(original, 1);
    });
  }

  test('bypass joins an already running attempt and cannot rerun completion',
      () async {
    final gate = Completer<void>();
    var calls = 0;
    final first = Do.oncePerSession(
        key: key('running'),
        function: () async {
          calls++;
          await gate.future;
        });
    final second = Do.oncePerSession(
        key: key('running'), bypassQueue: true, function: () => calls += 100);
    gate.complete();
    await Future.wait([first, second]);
    await Do.oncePerSession(
        key: key('running'), bypassQueue: true, function: () => calls += 100);
    expect(calls, 1);
  });

  test('onceAndDone can promote a pending once with the original function',
      () async {
    final gate = Completer<void>();
    final blocker =
        Do.oncePerSession(key: key('block'), function: () => gate.future);
    var original = 0;
    var replacement = 0;
    final pending = Do.once(key: key('alias'), function: () => original++);
    final promoted = Do.onceAndDone(
        key: key('alias'), bypassQueue: true, function: () => replacement++);
    await Future.wait([pending, promoted]);
    expect(original, 1);
    expect(replacement, 0);
    gate.complete();
    await blocker;
    await Future<void>.delayed(Duration.zero);
    expect(original, 1);
  });

  test('a failed marker write does not stop the queue and can be retried',
      () async {
    SharedPreferencesStorePlatform.instance = FailFirstWriteStore();
    final gate = Completer<void>();
    final started = Completer<void>();
    final first = Do.once(
        key: key('failing'),
        function: () {
          started.complete();
          return gate.future;
        });
    final failure = expectLater(first, throwsStateError);
    await started.future;
    var otherRan = false;
    final other =
        Do.oncePerSession(key: key('other'), function: () => otherRan = true);
    gate.complete();
    await Future.wait([failure, other]);
    expect(otherRan, true);
    var retried = false;
    await Do.once(key: key('failing'), function: () => retried = true);
    expect(retried, true);
  });

  for (final fail in [false, true]) {
    test(
        'promoted next day waits for earlier pending day after ${fail ? 'failure' : 'success'}',
        () async {
      final gate = Completer<void>();
      final order = <String>[];
      final blocker =
          Do.oncePerSession(key: key('block'), function: () => gate.future);
      final old = withClock(
          Clock.fixed(DateTime(2024, 1, 1)),
          () => Do.oncePerDay(
              key: key('daily'),
              function: () {
                order.add('old');
                if (fail) throw StateError('old');
              }));
      final oldCheck = fail
          ? expectLater(old, throwsStateError)
          : expectLater(old, completes);
      final next = withClock(
          Clock.fixed(DateTime(2024, 1, 2)),
          () => Do.oncePerDay(
              key: key('daily'), function: () => order.add('next')));
      final promoted = withClock(
          Clock.fixed(DateTime(2024, 1, 2)),
          () => Do.oncePerDay(
              key: key('daily'),
              bypassQueue: true,
              function: () => order.add('wrong')));
      expect(order, isEmpty);
      gate.complete();
      await Future.wait([blocker, oldCheck, next, promoted]);
      expect(order, ['old', 'next']);
    });
  }
}
