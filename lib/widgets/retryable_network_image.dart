import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 用 Dio 整包拉图 + PNG 魔数校验，避免 CachedNetworkImage 并行下载截断（常见于最后一张）。
class RetryableNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Color? errorIconColor;
  final bool darkErrorStyle;
  final VoidCallback? onTap;

  const RetryableNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.errorIconColor,
    this.darkErrorStyle = false,
    this.onTap,
  });

  @override
  State<RetryableNetworkImage> createState() => _RetryableNetworkImageState();
}

class _RetryableNetworkImageState extends State<RetryableNetworkImage> {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.bytes,
      headers: const {'Accept': 'image/png,image/*,*/*'},
    ),
  );

  /// 限制并行拉图，减少局域网下「最后一张被截断」概率
  static Future<void> _gate = Future.value();
  static Future<T> _withGate<T>(Future<T> Function() run) {
    final start = _gate;
    final done = Completer<void>();
    _gate = done.future;
    return start.then((_) => run()).whenComplete(() {
      if (!done.isCompleted) done.complete();
    });
  }

  static const _pngMagic = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  /// 标准 PNG 结尾：len=0 + IEND + CRC
  static const _pngIend = [
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ];

  Uint8List? _bytes;
  String? _error;
  bool _loading = true;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant RetryableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _bytes = null;
      _error = null;
      _attempt = 0;
      _load();
    }
  }

  bool _isCompletePng(Uint8List bytes) {
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

  String _hexHead(Uint8List bytes, [int n = 8]) {
    final take = bytes.length < n ? bytes.length : n;
    return bytes
        .sublist(0, take)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
  }

  Future<void> _load() async {
    final url = widget.imageUrl;
    setState(() {
      _loading = true;
      _error = null;
    });

    const maxAttempts = 3;
    Object? lastErr;

    for (var i = 1; i <= maxAttempts; i++) {
      _attempt = i;
      try {
        debugPrint('[ImgLoad] try#$i GET $url');
        final res = await _withGate(
          () => _dio.get<List<int>>(url),
        );
        final status = res.statusCode ?? 0;
        final raw = res.data ?? const <int>[];
        final bytes = Uint8List.fromList(raw);
        final ctype = res.headers.value('content-type') ?? '';
        final declared = res.headers.value('content-length');
        final declaredN = int.tryParse(declared ?? '');

        debugPrint(
          '[ImgLoad] try#$i status=$status ctype=$ctype '
          'bytes=${bytes.length} content-length=$declared '
          'head=${_hexHead(bytes)} url=$url',
        );

        if (status < 200 || status >= 300) {
          throw StateError('HTTP $status');
        }
        if (declaredN != null && declaredN > 0 && bytes.length != declaredN) {
          throw StateError(
            'truncated body ${bytes.length}/$declaredN',
          );
        }
        if (!_isCompletePng(bytes)) {
          final preview = String.fromCharCodes(
            bytes.take(60).where((b) => b >= 32 && b < 127),
          );
          throw StateError(
            'incomplete PNG missing IEND '
            '(head=${_hexHead(bytes)} tail=${_hexHead(Uint8List.sublistView(bytes, bytes.length - 12))} ascii="$preview")',
          );
        }

        if (!mounted) return;
        setState(() {
          _bytes = bytes;
          _loading = false;
          _error = null;
        });
        debugPrint('[ImgLoad] OK try#$i bytes=${bytes.length} $url');
        return;
      } catch (e) {
        lastErr = e;
        debugPrint('[ImgLoad] FAIL try#$i $url → $e');
        if (i < maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 250 * i));
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _bytes = null;
      _error = lastErr?.toString() ?? '加载失败';
    });
  }

  Future<void> _retry() async {
    if (_loading) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = widget.errorIconColor ??
        (widget.darkErrorStyle ? Colors.white70 : AppTheme.accent);

    if (_loading) {
      return Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.darkErrorStyle ? Colors.white : AppTheme.accent,
          ),
        ),
      );
    }

    if (_bytes != null) {
      final image = Image.memory(
        _bytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
      );
      if (widget.onTap == null) return image;
      return GestureDetector(onTap: widget.onTap, child: image);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _retry,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: errorColor, size: 36),
                const SizedBox(height: 8),
                Text(
                  '加载失败',
                  style: TextStyle(
                    color: errorColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '点我重试 · 已试$_attempt次',
                  style: TextStyle(
                    color: errorColor.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: errorColor.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
