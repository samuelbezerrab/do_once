library flutter_execution;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
    _isInitialized = true;
  }

  Future<void> doOnceForever({
    required String key,
    required FutureOr<dynamic> Function() function,
  }) async {
    bool _done = _preferences.getBool('${_preferencesKey}_$key') ?? false;

    if (_isInitialized) {
      if (_done == false) {
        print('[Execution] Calling function "$key".');
        await function.call();
        await _preferences.setBool('${_preferencesKey}_$key', true);

      } else {
        print('[Execution] Function "$key" has already been performed.');
      }
    } else {
      throw Exception(
          '[Execution] \'doOnceForever\' called before Execution is initialized.');
    }
  }

  Future<void> doOnceOnSession({
    required String key,
    required FutureOr<dynamic> Function() function,
  }) async {
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
