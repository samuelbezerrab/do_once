library flutter_execution;

import 'package:shared_preferences/shared_preferences.dart';

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
    required void Function() function,
  }) async {
    bool _done = _preferences.getBool('${_preferencesKey}_$key') ?? false;

    if (_isInitialized) {
      if (_done == false) {
        await _preferences.setBool('${_preferencesKey}_$key', true);

        print('[Execution] Calling function "$key".');
        function.call();
      } else {
        print('[Execution] Function "$key" has already been performed.');
      }
    } else{
      throw Exception(
          '[Execution] \'doOnceForever\' called before Execution is initialized.');
    }
  }

  Future<void> doOnceOnSession({
    required String key,
    required void Function() function,
  }) async {
    if (_isInitialized) {
      if (_sessionCache[key] == null || _sessionCache[key] == false) {
        _sessionCache[key] = true;
        print('[Execution] Calling function "$key".');
        function.call();
      } else {
        print('[Execution] Function "$key" has already been performed.');
      }
    } else {
      throw Exception(
          '[Execution] \'doOnceOnSession\' called before Execution is initialized.');
    }
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
