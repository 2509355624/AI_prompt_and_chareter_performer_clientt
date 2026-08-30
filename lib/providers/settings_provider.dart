import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

/// 设置 Provider：管理服务器地址、API Key 等配置
class SettingsProvider extends ChangeNotifier {
  final ApiService _api;
  String _serverUrl = '';
  String _apiKey = '';
  String _aiProvider = 'deepseek';
  String _aiModel = '';
  String _aiBaseUrl = '';
  bool _isConnected = false;

  SettingsProvider(this._api);

  String get serverUrl => _serverUrl;
  String get apiKey => _apiKey;
  String get aiProvider => _aiProvider;
  String get aiModel => _aiModel;
  String get aiBaseUrl => _aiBaseUrl;
  bool get isConnected => _isConnected;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _serverUrl = prefs.getString('server_url') ?? 'http://192.168.1.100:3000';
    _apiKey = prefs.getString('api_key') ?? '';
    _aiProvider = prefs.getString('ai_provider') ?? 'deepseek';
    _aiModel = prefs.getString('ai_model') ?? '';
    _aiBaseUrl = prefs.getString('ai_base_url') ?? '';

    if (_serverUrl.isNotEmpty) {
      _api.setBaseUrl(_serverUrl);
      // 尝试连接
      _isConnected = await _api.checkConnection();
    }
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    _serverUrl = url;
    _api.setBaseUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', url);
    _isConnected = await _api.checkConnection();
    notifyListeners();
  }

  Future<void> setAiConfig({
    required String provider,
    required String apiKey,
    required String model,
    required String baseUrl,
  }) async {
    _aiProvider = provider;
    _apiKey = apiKey;
    _aiModel = model;
    _aiBaseUrl = baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_provider', provider);
    await prefs.setString('api_key', apiKey);
    await prefs.setString('ai_model', model);
    await prefs.setString('ai_base_url', baseUrl);
    notifyListeners();
  }

  Future<bool> testConnection(String url) async {
    final oldUrl = _serverUrl;
    _api.setBaseUrl(url);
    final ok = await _api.checkConnection();
    if (!ok) {
      _api.setBaseUrl(oldUrl);
    }
    return ok;
  }
}
