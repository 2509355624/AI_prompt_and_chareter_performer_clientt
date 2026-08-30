import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 进程内原图缓存：同一 URL 只向服务端 GET 一次，放大/保存复用内存字节。
/// 不做磁盘缓存，避免 5MB×N 把安装包/缓存目录撑大。
class ImageBytesCache {
  ImageBytesCache._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.bytes,
      headers: const {'Accept': 'image/png,image/*,*/*'},
    ),
  );

  static const _pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  static const _pngIend = [
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ];

  static const int maxEntries = 12;
  static final LinkedHashMap<String, Uint8List> _raw = LinkedHashMap();
  static final LinkedHashMap<String, Uint8List> _framed = LinkedHashMap();
  static final Map<String, Future<Uint8List>> _inflight = {};

  static bool _isCompletePng(Uint8List bytes) {
    if (bytes.length < 100) return false;
    for (var i = 0; i < _pngMagic.length; i++) {
      if (bytes[i] != _pngMagic[i]) return false;
    }
    final start = bytes.length - _pngIend.length;
    for (var i = 0; i < _pngIend.length; i++) {
      if (bytes[start + i] != _pngIend[i]) return false;
    }
    return true;
  }

  static void _touchPut(LinkedHashMap<String, Uint8List> map, String key, Uint8List value) {
    map.remove(key);
    map[key] = value;
    while (map.length > maxEntries) {
      map.remove(map.keys.first);
    }
  }

  /// 原图：有缓存直接返回；否则 GET 一次并校验 IEND。
  static Future<Uint8List> getRaw(String url) {
    final cached = _raw[url];
    if (cached != null) {
      // LRU touch
      _raw.remove(url);
      _raw[url] = cached;
      debugPrint('[ImgCache] HIT raw ${cached.length}B $url');
      return Future.value(cached);
    }

    final existing = _inflight[url];
    if (existing != null) return existing;

    final future = () async {
      debugPrint('[ImgCache] MISS GET $url');
      final res = await _dio.get<List<int>>(url);
      final bytes = Uint8List.fromList(res.data ?? const []);
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw StateError('HTTP $status');
      }
      final declared = int.tryParse(res.headers.value('content-length') ?? '');
      if (declared != null && declared > 0 && bytes.length != declared) {
        throw StateError('truncated ${bytes.length}/$declared');
      }
      if (!_isCompletePng(bytes)) {
        throw StateError('incomplete PNG missing IEND (${bytes.length}B)');
      }
      _touchPut(_raw, url, bytes);
      debugPrint('[ImgCache] STORE raw ${bytes.length}B $url');
      return bytes;
    }();

    _inflight[url] = future;
    return future.whenComplete(() => _inflight.remove(url));
  }

  static Uint8List? peekRaw(String url) => _raw[url];

  static Uint8List? peekFramed(String key) => _framed[key];

  static void putFramed(String key, Uint8List bytes) {
    _touchPut(_framed, key, bytes);
  }

  static void clear() {
    _raw.clear();
    _framed.clear();
    _inflight.clear();
  }
}
