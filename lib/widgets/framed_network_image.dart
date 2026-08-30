import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/image_bytes_cache.dart';
import '../utils/sticker_frame.dart';

/// 预览组件：原图经 [ImageBytesCache] 只拉一次；边框在本地合成并可复用。
class FramedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final bool showFrame;
  final BoxFit fit;
  final VoidCallback? onTap;

  const FramedNetworkImage({
    super.key,
    required this.imageUrl,
    this.showFrame = true,
    this.fit = BoxFit.contain,
    this.onTap,
  });

  @override
  State<FramedNetworkImage> createState() => _FramedNetworkImageState();
}

class _FramedNetworkImageState extends State<FramedNetworkImage> {
  Uint8List? _displayBytes;
  String? _error;
  bool _loading = true;

  String get _frameKey =>
      '${widget.imageUrl}|frame|900|${widget.showFrame ? 1 : 0}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FramedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.showFrame != widget.showFrame) {
      _load();
    }
  }

  Future<void> _load() async {
    // 同步命中：零闪烁
    if (widget.showFrame) {
      final framed = ImageBytesCache.peekFramed(_frameKey);
      if (framed != null) {
        setState(() {
          _displayBytes = framed;
          _loading = false;
          _error = null;
        });
        return;
      }
    } else {
      final raw = ImageBytesCache.peekRaw(widget.imageUrl);
      if (raw != null) {
        setState(() {
          _displayBytes = raw;
          _loading = false;
          _error = null;
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final raw = await ImageBytesCache.getRaw(widget.imageUrl);
      Uint8List out = raw;
      if (widget.showFrame) {
        final cachedFrame = ImageBytesCache.peekFramed(_frameKey);
        if (cachedFrame != null) {
          out = cachedFrame;
        } else {
          out = await renderStickerPng(
            raw,
            options: const StickerFrameOptions.paperCollage(maxContentWidth: 900),
          );
          ImageBytesCache.putFramed(_frameKey, out);
          debugPrint(
            '[FrameImg] composed frame ${out.length}B from cache raw',
          );
        }
      }

      if (!mounted) return;
      setState(() {
        _displayBytes = out;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[FrameImg] FAIL ${widget.imageUrl} → $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.accent,
          ),
        ),
      );
    }
    if (_displayBytes != null) {
      final image = Image.memory(
        _displayBytes!,
        fit: widget.fit,
        gaplessPlayback: true,
      );
      if (widget.onTap == null) return image;
      return GestureDetector(onTap: widget.onTap, child: image);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _load,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image_outlined, color: AppTheme.accent),
                const SizedBox(height: 8),
                const Text('加载失败', style: TextStyle(color: AppTheme.accent)),
                const SizedBox(height: 4),
                const Text(
                  '点我重试',
                  style: TextStyle(fontSize: 12, color: AppTheme.text2),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textMute,
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
