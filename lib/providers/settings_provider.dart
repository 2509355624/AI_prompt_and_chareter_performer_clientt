import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// 仅管理「连哪台电脑上的 Node」。密钥全部在服务端 .env。
class SettingsProvider extends ChangeNotifier {
  final ApiService _api;

  static const defaultServerUrl = 'http://192.168.0.128:3000';

  String _serverUrl = '';
  bool _isConnected = false;
  bool _loaded = false;

  SettingsProvider(this._api);

  String get serverUrl => _serverUrl;
  bool get isConnected => _isConnected;
  bool get loaded => _loaded;
  bool get hasServerUrl => _serverUrl.trim().isNotEmpty;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // 清掉豆包那版误存在手机里的密钥
    await prefs.remove('api_key');
    await prefs.remove('ai_provider');
    await prefs.remove('ai_model');
    await prefs.remove('ai_base_url');

    _serverUrl = prefs.getString('server_url') ?? defaultServerUrl;
    if (_serverUrl.isNotEmpty) {
      _api.setBaseUrl(_serverUrl);
      _isConnected = await _api.checkConnection();
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    _serverUrl = normalized;
    _api.setBaseUrl(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', normalized);
    _isConnected = await _api.checkConnection();
    notifyListeners();
  }

  Future<bool> testAndSave(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    final old = _serverUrl;
    _api.setBaseUrl(normalized);
    final ok = await _api.checkConnection();
    if (!ok) {
      if (old.isNotEmpty) _api.setBaseUrl(old);
      return false;
    }
    await setServerUrl(normalized);
    return true;
  }

  Future<void> refreshConnection() async {
    if (_serverUrl.isEmpty) {
      _isConnected = false;
      notifyListeners();
      return;
    }
    _api.setBaseUrl(_serverUrl);
    _isConnected = await _api.checkConnection();
    notifyListeners();
  }
}
