library flutter_execution;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:queue/queue.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ExecutionScope { session, forever, daily }

class Execution {
  Execution._internal();

  static final Execution _instance = Execution._internal();

  static Execution get instance => _instance;
  bool get isInitialized => _isInitialized;

  static late SharedPreferences _preferences;
  static bool _isInitialized = false;
  static const String _preferencesKey = 'A2S-Execution';
  static late Map<String, bool> _sessionCache = {};
  static final Map<String, List<_Attempt>> _sessionAttempts = {};
  static final Map<String, List<_Attempt>> _foreverAttempts = {};
  static final Map<String, List<_Attempt>> _dailyAttempts = {};
  static final Set<String> _unconfirmedWrites = {};
  static late Queue _workQueue;
  static bool _closing = false;
  static bool _initializing = false;
  static int? _maxConcurrent;
  static Future<void>? _disposing;
  static final Set<Future<void>> _accepted = {};

  bool _isMarkedDone(String key) =>
      !_unconfirmedWrites.contains(key) && (_preferences.getBool(key) ?? false);

  Future<void> _markDone(String key) async {
    // SharedPreferences updates its cache before the platform write finishes.
    _unconfirmedWrites.add(key);
    if (!await _preferences.setBool(key, true)) {
      throw StateError('Failed to persist execution marker for "$key".');
    }
    _unconfirmedWrites.remove(key);
  }

  Future<void> initialize({int maxConcurrent = 1}) async {
    if (maxConcurrent < 1)
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent');
    if (_initializing ||
        _closing ||
        (_isInitialized && _maxConcurrent != maxConcurrent)) {
      throw StateError(
          'Cannot initialize with a different configuration or while closing.');
    }
    if (_isInitialized && _accepted.isNotEmpty) return;
    _initializing = true;
    try {
      _preferences = await SharedPreferences.getInstance();
      if (!_isInitialized) _workQueue = Queue(parallel: maxConcurrent);
      _maxConcurrent = maxConcurrent;
      _isInitialized = true;
    } finally {
      _initializing = false;
    }
  }

  bool hasExecuted({required String key, required ExecutionScope scope}) {
    if (!_isInitialized) {
      throw StateError(
          '[Execution] Query called before Execution is initialized.');
    }
    if (scope == ExecutionScope.session) return _sessionCache[key] == true;
    if (scope == ExecutionScope.forever) {
      return _isMarkedDone('${_preferencesKey}_$key');
    }
    return _isMarkedDone(_dailyKey(key, clock.now()));
  }

  static String _day(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _dailyKey(String key, DateTime date) =>
      '$_preferencesKey-daily-v2_${_day(date)}_$key';

  Future<void> doOnceForever({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) {
    return _coordinate(_foreverAttempts, key, '', () async {
      if (_isInitialized) {
        final fullKey = '${_preferencesKey}_$key';
        final _done = _isMarkedDone(fullKey);
        if (_done == false) {
          print('[Execution] Calling function "$key".');
          await function.call();
          await _markDone(fullKey);
        } else {
          print('[Execution] Function "$key" has already been performed.');
        }
      } else {
        throw Exception(
            '[Execution] \'doOnceForever\' called before Execution is initialized.');
      }
    }, bypassQueue);
  }

  Future<void> doOnceOnSession({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) {
    return _coordinate(_sessionAttempts, key, '', () async {
      if (_isInitialized) {
        if (_sessionCache[key] == null || _sessionCache[key] == false) {
          print('[Execution] Calling function "$key".');
          await function.call();
          _sessionCache[key] = true;
        } else {
          print('[Execution] Function "$key" has already been performed.');
        }
      } else {
        throw Exception(
            '[Execution] \'doOnceOnSession\' called before Execution is initialized.');
      }
    }, bypassQueue);
  }

  Future<void> doDaily({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) {
    final today = clock.now();
    final todayKey = _day(today);
    final fullKey = _dailyKey(key, today);
    return _coordinate(_dailyAttempts, key, todayKey, () async {
      if (_isInitialized) {
        final _done = _isMarkedDone(fullKey);
        if (_done == false) {
          print('[Execution] Calling function "$key".');
          await function.call();
          await _markDone(fullKey);
        } else {
          print(
              '[Execution] Function "$key" has already been performed today.');
        }
      } else {
        throw Exception(
            '[Execution] \'doDaily\' called before Execution is initialized.');
      }
    }, bypassQueue);
  }

  Future<void> revokeKey(String key) async {
    if (_preferences.containsKey('${_preferencesKey}_$key')) {
      await _preferences.setBool('${_preferencesKey}_$key', false);
    }

    if (_sessionCache.containsKey(key)) {
      _sessionCache[key] = false;
    }

    print('[Execution] Function "$key" has been revoked.');
  }

  Future<void> dispose() {
    if (_disposing != null) return _disposing!;
    if (!_isInitialized || _initializing) {
      return Future.error(StateError('Dispose called before initialization.'));
    }
    _closing = true;
    return _disposing = () async {
      try {
        await Future.wait(_accepted
            .map((future) => future.then<void>((_) {},
                onError: (Object error, StackTrace stack) {}))
            .toList());
        _sessionCache.clear();
      } finally {
        _isInitialized = false;
        _closing = false;
        _disposing = null;
      }
    }();
  }
}

class _Attempt {
  _Attempt(this.period);

  final String period;
  final Completer<void> completer = Completer<void>();
  bool started = false;
  bool bypass = false;
  bool eligible = false;
  late void Function() schedule;
}

Future<void> _coordinate(Map<String, List<_Attempt>> attempts, String key,
    String period, Future<void> Function() action, bool bypass) {
  if (!Execution._isInitialized ||
      Execution._closing ||
      Execution._initializing) {
    return Future.error(StateError('Execution is not accepting actions.'));
  }
  final queue = attempts.putIfAbsent(key, () => <_Attempt>[]);
  for (final attempt in queue) {
    if (attempt.period == period) {
      if (bypass && !attempt.started) {
        attempt.bypass = true;
        if (attempt.eligible) attempt.schedule();
      }
      return attempt.completer.future;
    }
  }
  final previous = queue.isEmpty ? null : queue.last;
  final attempt = _Attempt(period);
  attempt.bypass = bypass;
  queue.add(attempt);
  final future = attempt.completer.future;
  Execution._accepted.add(future);
  Future<void> run() async {
    if (attempt.started) return;
    attempt.started = true;
    try {
      await action();
      queue.remove(attempt);
      if (queue.isEmpty) attempts.remove(key);
      attempt.completer.complete();
    } catch (error, stack) {
      queue.remove(attempt);
      if (queue.isEmpty) attempts.remove(key);
      attempt.completer.completeError(error, stack);
    }
    Execution._accepted.remove(future);
  }

  attempt.schedule = () {
    if (attempt.started) return;
    if (attempt.bypass) {
      run();
    } else {
      Execution._workQueue.add<void>(run);
    }
  };
  if (previous == null) {
    attempt.eligible = true;
    attempt.schedule();
  } else {
    previous.completer.future
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {})
        .then((_) {
      attempt.eligible = true;
      attempt.schedule();
    });
  }
  return future;
}
