import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The independent periods in which an action can be completed.
enum DoScope { session, forever, daily, hourly, monthly, yearly }

/// Runs keyed actions once per scope and period in this isolate.
///
/// Persistent completion markers are loaded automatically when needed. A
/// callback is marked complete only after it and the marker write succeed.
abstract final class Do {
  static const String _preferencesPrefix = 'do_once_';
  static final Set<String> _sessionCompleted = {};
  static final Map<DoScope, Map<String, List<_Attempt>>> _attempts = {};
  static final Set<String> _unconfirmedWrites = {};
  static final _WorkQueue _workQueue = _WorkQueue();

  /// Changes the maximum number of queued actions running concurrently.
  ///
  /// The default is one. Increasing the limit starts waiting actions as slots
  /// become available; reducing it does not interrupt actions already running.
  /// Actions using `bypassQueue` do not count against this limit.
  static void configure({required int maxConcurrent}) {
    if (maxConcurrent < 1) {
      throw ArgumentError.value(maxConcurrent, 'maxConcurrent');
    }
    _workQueue.maxConcurrent = maxConcurrent;
  }

  /// Runs [function] once for [key], recording completion persistently.
  static Future<void> once({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) =>
      _execute(DoScope.forever, key, function, bypassQueue);

  /// An alias for [once], sharing the same key, scope, and execution attempt.
  static Future<void> onceAndDone({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) =>
      once(key: key, function: function, bypassQueue: bypassQueue);

  /// Runs [function] once for [key] during this isolate's lifetime.
  static Future<void> oncePerSession({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) =>
      _execute(DoScope.session, key, function, bypassQueue);

  /// Runs [function] once for [key] on the local calendar day of this call.
  static Future<void> oncePerDay({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) =>
      _execute(DoScope.daily, key, function, bypassQueue);

  /// Runs [function] once for [key] during the local calendar hour of this call.
  static Future<void> oncePerHour({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) =>
      _execute(DoScope.hourly, key, function, bypassQueue);

  /// Runs [function] once for [key] during the local calendar month of this call.
  static Future<void> oncePerMonth({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) =>
      _execute(DoScope.monthly, key, function, bypassQueue);

  /// Runs [function] once for [key] during the local calendar year of this call.
  static Future<void> oncePerYear({
    required String key,
    required FutureOr<dynamic> Function() function,
    bool bypassQueue = false,
  }) =>
      _execute(DoScope.yearly, key, function, bypassQueue);

  static Future<void> _execute(DoScope scope, String key,
      FutureOr<dynamic> Function() function, bool bypassQueue) {
    final period = _period(scope);
    final attempts = _attempts.putIfAbsent(scope, () => {});
    return _coordinate(attempts, key, period, () async {
      if (scope == DoScope.session) {
        if (!_sessionCompleted.contains(key)) {
          await function();
          _sessionCompleted.add(key);
        }
        return;
      }
      final fullKey = _storageKey(scope, key, period);
      final preferences = await SharedPreferences.getInstance();
      if (!_isMarkedDone(preferences, fullKey)) {
        await function();
        await _markDone(preferences, fullKey);
      }
    }, bypassQueue);
  }

  /// Reports whether [key] has completed in [scope] and the current period.
  ///
  /// A pending action or marker write is not considered complete. Querying and
  /// executing are separate operations and do not provide mutual exclusion.
  static Future<bool> hasExecuted({
    required String key,
    required DoScope scope,
  }) async {
    if (scope == DoScope.session) return _sessionCompleted.contains(key);
    final fullKey = _storageKey(scope, key, _period(scope));
    final preferences = await SharedPreferences.getInstance();
    return _isMarkedDone(preferences, fullKey);
  }

  /// Revokes [key] in [scope], using the current local calendar period.
  ///
  /// Revocation does not wait for an action already in progress, which may
  /// subsequently record its completion.
  static Future<void> revoke({
    required String key,
    required DoScope scope,
  }) async {
    if (scope == DoScope.session) {
      _sessionCompleted.remove(key);
      return;
    }
    final fullKey = _storageKey(scope, key, _period(scope));
    final preferences = await SharedPreferences.getInstance();
    if (preferences.containsKey(fullKey) &&
        !await preferences.setBool(fullKey, false)) {
      throw StateError('Failed to revoke execution marker for "$fullKey".');
    }
  }

  static bool _isMarkedDone(SharedPreferences preferences, String key) =>
      !_unconfirmedWrites.contains(key) && (preferences.getBool(key) ?? false);

  static Future<void> _markDone(
      SharedPreferences preferences, String key) async {
    // SharedPreferences updates its cache before the platform write finishes.
    _unconfirmedWrites.add(key);
    if (!await preferences.setBool(key, true)) {
      throw StateError('Failed to persist execution marker for "$key".');
    }
    _unconfirmedWrites.remove(key);
  }

  static String _period(DoScope scope) {
    if (scope == DoScope.session || scope == DoScope.forever) return '';
    final now = clock.now();
    final month = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final day = '$month-${now.day.toString().padLeft(2, '0')}';
    return switch (scope) {
      DoScope.hourly => '$day-${now.hour.toString().padLeft(2, '0')}',
      DoScope.daily => day,
      DoScope.monthly => month,
      DoScope.yearly => '${now.year}',
      DoScope.session || DoScope.forever => '',
    };
  }

  static String _storageKey(DoScope scope, String key, String period) =>
      switch (scope) {
        DoScope.forever => '${_preferencesPrefix}forever_$key',
        DoScope.daily => '${_preferencesPrefix}daily_v2_${period}_$key',
        DoScope.hourly => '${_preferencesPrefix}hourly_${period}_$key',
        DoScope.monthly => '${_preferencesPrefix}monthly_${period}_$key',
        DoScope.yearly => '${_preferencesPrefix}yearly_${period}_$key',
        DoScope.session =>
          throw StateError('Session markers are not persistent.'),
      };
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
  final attemptsForKey = attempts.putIfAbsent(key, () => <_Attempt>[]);
  for (final attempt in attemptsForKey) {
    if (attempt.period == period) {
      if (bypass && !attempt.started) {
        attempt.bypass = true;
        if (attempt.eligible) attempt.schedule();
      }
      return attempt.completer.future;
    }
  }
  final previous = attemptsForKey.isEmpty ? null : attemptsForKey.last;
  final attempt = _Attempt(period)..bypass = bypass;
  attemptsForKey.add(attempt);

  Future<void> run() async {
    if (attempt.started) return;
    attempt.started = true;
    try {
      await action();
      attemptsForKey.remove(attempt);
      if (attemptsForKey.isEmpty) attempts.remove(key);
      attempt.completer.complete();
    } catch (error, stack) {
      attemptsForKey.remove(attempt);
      if (attemptsForKey.isEmpty) attempts.remove(key);
      attempt.completer.completeError(error, stack);
    }
  }

  attempt.schedule = () {
    if (attempt.started) return;
    if (attempt.bypass) {
      run();
    } else {
      Do._workQueue.add(run);
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
  return attempt.completer.future;
}

class _WorkQueue {
  final Queue<Future<void> Function()> _pending = Queue();
  int _maxConcurrent = 1;
  int _running = 0;
  bool _draining = false;

  set maxConcurrent(int value) {
    _maxConcurrent = value;
    _drain();
  }

  void add(Future<void> Function() action) {
    _pending.addLast(action);
    _drain();
  }

  void _drain() {
    if (_draining) return;
    _draining = true;
    try {
      while (_running < _maxConcurrent && _pending.isNotEmpty) {
        final action = _pending.removeFirst();
        _running++;
        action().whenComplete(() {
          _running--;
          _drain();
        });
      }
    } finally {
      _draining = false;
    }
  }
}
