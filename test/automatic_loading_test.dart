import 'dart:async';

import 'package:do_once/do_once.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class DelayedStore extends InMemorySharedPreferencesStore {
  DelayedStore() : super.empty();
  final started = Completer<void>();
  final gate = Completer<void>();
  int reads = 0;

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    started.complete();
    await gate.future;
    return super.getAll();
  }
}

class FailFirstLoadStore extends InMemorySharedPreferencesStore {
  FailFirstLoadStore() : super.empty();
  int reads = 0;

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    if (reads == 1) throw StateError('load failed');
    return super.getAll();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Do.configure(maxConcurrent: 1);
  });

  test('session operations need no preferences access', () async {
    final store = FailFirstLoadStore();
    SharedPreferencesStorePlatform.instance = store;
    await Do.oncePerSession(key: 'session', function: () {});
    expect(await Do.hasExecuted(key: 'session', scope: DoScope.session), true);
    await Do.revoke(key: 'session', scope: DoScope.session);
    expect(store.reads, 0);
  });

  test(
      'overlapping initial calls share preference loading and the first action',
      () async {
    final store = DelayedStore();
    SharedPreferencesStorePlatform.instance = store;
    var calls = 0;
    final first = Do.once(key: 'lazy', function: () => calls++);
    final second = Do.onceAndDone(key: 'lazy', function: () => calls += 100);
    final query = Do.hasExecuted(key: 'lazy', scope: DoScope.forever);
    await store.started.future;
    expect(store.reads, 1);
    store.gate.complete();
    await Future.wait([first, second]);
    await query;
    expect(calls, 1);
    expect(store.reads, 1);
  });

  test('a storage load failure is propagated and later calls can retry',
      () async {
    final store = FailFirstLoadStore();
    SharedPreferencesStorePlatform.instance = store;
    await expectLater(
        Do.once(key: 'load-failure', function: () {}), throwsStateError);
    var calls = 0;
    await Do.once(key: 'load-failure', function: () => calls++);
    expect(calls, 1);
    expect(store.reads, 2);
  });

  test('query can be the first persistent operation', () async {
    expect(await Do.hasExecuted(key: 'unknown', scope: DoScope.forever), false);
  });

  test('revocation can be the first persistent operation', () async {
    await Do.revoke(key: 'unknown', scope: DoScope.daily);
  });
}
