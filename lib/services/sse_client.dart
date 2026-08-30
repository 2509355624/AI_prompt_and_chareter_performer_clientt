import 'dart:async';
import 'dart:convert';

/// SSE 客户端
/// 用于订阅对话进度和出图进度
class SseClient {
  final String url;
  final Map<String, String> headers;

  SseClient(this.url, {this.headers = const {}});

  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  bool _isConnected = false;
  bool _shouldReconnect = true;

  Stream<Map<String, dynamic>> get stream => _controller.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    _shouldReconnect = true;
    await _connect();
  }

  Future<void> _connect() async {
    try {
      final uri = Uri.parse(url);
      // 这里我们用一个简单的 HTTP 请求 + 流处理
      // 实际实现中使用 HttpClient 或 dio
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      if (_shouldReconnect) {
        await Future.delayed(const Duration(seconds: 2));
        if (_shouldReconnect) await _connect();
      }
    }
  }

  /// 从 SSE 数据流中解析事件
  static Map<String, dynamic>? parseSseLine(String line) {
    if (line.startsWith('data: ')) {
      final dataStr = line.substring(6).trim();
      if (dataStr.isEmpty) return null;
      try {
        return jsonDecode(dataStr) as Map<String, dynamic>;
      } catch (_) {
        return {'raw': dataStr};
      }
    }
    return null;
  }

  void dispose() {
    _shouldReconnect = false;
    _isConnected = false;
    _controller.close();
  }
}
