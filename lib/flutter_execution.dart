library flutter_execution;

import 'dart:async';

import 'package:clock/clock.dart';
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

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    _isInitialized = true;
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
    });
  }

  Future<void> doOnceOnSession({
    required String key,
    required FutureOr<dynamic> Function() function,
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
    });
  }

  Future<void> doDaily({
    required String key,
    required FutureOr<dynamic> Function() function,
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
    });
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

  Future<void> dispose() async {
    if (_isInitialized) {
      print('[Execution] Disposing preferences.');
      _sessionCache.clear();
      await _preferences.clear();
    } else {
      throw Exception(
          '[Execution] Dispose called before Execution is initialized.');
    }
  }
}

class _Attempt {
  _Attempt(this.period);

  final String period;
  final Completer<void> completer = Completer<void>();
}

Future<void> _coordinate(Map<String, List<_Attempt>> attempts, String key,
    String period, Future<void> Function() action) {
  final queue = attempts.putIfAbsent(key, () => <_Attempt>[]);
  for (final attempt in queue) {
    if (attempt.period == period) return attempt.completer.future;
  }
  final previous = queue.isEmpty ? null : queue.last;
  final attempt = _Attempt(period);
  queue.add(attempt);
  // A callback must not call and await the same key and scope recursively.
  () async {
    if (previous != null) {
      try {
        await previous.completer.future;
      } catch (_) {
        // A later period gets its own attempt even if the earlier one failed.
      }
    }
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
  }();
  return attempt.completer.future;
}
