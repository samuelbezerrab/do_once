library flutter_execution;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ExecutionMode { onceForever, onceOnSession }

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
  static final Set<String> _failedWrites = {};

  Future<void> _markDone(String key) async {
    try {
      if (!await _preferences.setBool(key, true)) {
        throw StateError('Failed to persist execution marker for "$key".');
      }
      _failedWrites.remove(key);
    } catch (_) {
      // SharedPreferences updates its cache before the platform write finishes.
      _failedWrites.add(key);
      rethrow;
    }
  }

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  Future<void> doOnceForever({
    required String key,
    required FutureOr<dynamic> Function() function,
  }) {
    return _coordinate(_foreverAttempts, key, '', () async {
      if (_isInitialized) {
        final fullKey = '${_preferencesKey}_$key';
        final _done = !_failedWrites.contains(fullKey) &&
            (_preferences.getBool(fullKey) ?? false);
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

  Future<void> doOnceWhenForeground({
    required String key,
    required ExecutionMode mode,
    required FutureOr<dynamic> Function() function,
  }) async {
    SystemChannels.lifecycle.setMessageHandler((message) async {
      if (message == 'AppLifecycleState.resumed') {
        if (mode == ExecutionMode.onceForever) {
          print('[Execution] App in Foreground! Calling doOnceForever method.');
          await doOnceForever(key: key, function: function);
        } else if (mode == ExecutionMode.onceOnSession) {
          print(
              '[Execution] App in Foreground! Calling doOnceOnSession method.');
          await doOnceOnSession(key: key, function: function);
        }
      }
      return Future.value('');
    });
  }

  Future<void> doDaily({
    required String key,
    required FutureOr<dynamic> Function() function,
  }) {
    final today = clock.now();
    final todayKey =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final fullKey = '$_preferencesKey-daily-v2_${todayKey}_$key';
    return _coordinate(_dailyAttempts, key, todayKey, () async {
      if (_isInitialized) {
        final _done = !_failedWrites.contains(fullKey) &&
            (_preferences.getBool(fullKey) ?? false);
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
