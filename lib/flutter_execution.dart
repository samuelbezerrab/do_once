library flutter_execution;

import 'package:shared_preferences/shared_preferences.dart';

class Execution {
  Execution._internal();

  static final Execution _instance = Execution._internal();

  static Execution get instance => _instance;
  bool get isInitialized => _isInitialized;

  static late SharedPreferences _preferences;
  // static late Map<String, dynamic> _remoteConfigCache;
  static bool _isInitialized = false;
  static const String _preferencesKey = 'Execution';

  Future<void> initialize() async {
    _preferences = await SharedPreferences.getInstance();
  }

  Future<void> doOnceForever({
    required String key,
    required void Function() function,
  }) async {
    bool _done = _preferences.getBool('${_preferencesKey}_$key') ?? false;

    if (_done == false) {
      _preferences.setBool('${_preferencesKey}_$key', true);
    }
  }

  Future<void> doOnceOnSession() async {}
}
