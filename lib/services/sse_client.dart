import 'dart:convert';

/// 解析 SSE：支持命名事件（`event:` + `data:`）与仅 `data:` 的流。
/// 输出的 Map 会带上 `event` 字段（若服务端发了事件名）。
class SseParser {
  String _buffer = '';
  String? _eventName;
  final List<String> _dataLines = [];

  /// 喂入原始字节块，返回本批解析出的事件。
  List<Map<String, dynamic>> push(List<int> chunk) {
    _buffer += utf8.decode(chunk, allowMalformed: true);
    final lines = _buffer.split('\n');
    _buffer = lines.removeLast();

    final out = <Map<String, dynamic>>[];
    for (var line in lines) {
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      if (line.isEmpty) {
        final event = _flush();
        if (event != null) out.add(event);
        continue;
      }
      if (line.startsWith(':')) continue; // comment / keepalive
      if (line.startsWith('event:')) {
        _eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        var data = line.substring(5);
        if (data.startsWith(' ')) data = data.substring(1);
        _dataLines.add(data);
      }
    }
    return out;
  }

  /// 流结束时冲刷残留。
  Map<String, dynamic>? finish() {
    if (_buffer.isNotEmpty) {
      var line = _buffer;
      _buffer = '';
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.startsWith('data:')) {
        var data = line.substring(5);
        if (data.startsWith(' ')) data = data.substring(1);
        _dataLines.add(data);
      }
    }
    return _flush();
  }

  Map<String, dynamic>? _flush() {
    if (_dataLines.isEmpty) {
      _eventName = null;
      return null;
    }
    final dataStr = _dataLines.join('\n').trim();
    final name = _eventName;
    _dataLines.clear();
    _eventName = null;
    if (dataStr.isEmpty || dataStr == '[DONE]') return null;

    try {
      final decoded = jsonDecode(dataStr);
      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        if (name != null && name.isNotEmpty) {
          map['event'] = name;
        }
        return map;
      }
      return {
        if (name != null && name.isNotEmpty) 'event': name,
        'data': decoded,
      };
    } catch (_) {
      return {
        if (name != null && name.isNotEmpty) 'event': name,
        'raw': dataStr,
      };
    }
  }
}

/// 从 Comfy / 任务 JSON 中抽出图片 URL 列表（兼容 `{url}` 对象与纯字符串）。
List<String> extractImageUrls(dynamic images) {
  return extractGenerateImages(images).map((e) => e.url).toList();
}

class GenerateImageRef {
  final String url;
  final String prompt;

  const GenerateImageRef({required this.url, this.prompt = ''});
}

/// 抽出带提示词的图片列表。
List<GenerateImageRef> extractGenerateImages(dynamic images) {
  if (images is! List) return const [];
  final out = <GenerateImageRef>[];
  for (final item in images) {
    if (item is String && item.isNotEmpty) {
      out.add(GenerateImageRef(url: item));
    } else if (item is Map) {
      final u = item['url']?.toString() ?? '';
      if (u.isEmpty) continue;
      out.add(GenerateImageRef(
        url: u,
        prompt: item['prompt']?.toString() ?? '',
      ));
    }
  }
  return out;
}
