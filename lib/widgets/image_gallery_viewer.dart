import 'package:flutter/material.dart';

import 'retryable_network_image.dart';
import 'sticker_widgets.dart';

/// 全屏大图预览：左右翻页 + 保存（不会抢输入框焦点）
Future<void> showImageGallery(
  BuildContext context, {
  required List<String> imageUrls,
  int initialIndex = 0,
  required Future<void> Function(int index) onSaveIndex,
}) {
  if (imageUrls.isEmpty) return Future.value();
  final index = initialIndex.clamp(0, imageUrls.length - 1);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close-gallery',
    barrierColor: Colors.black87,
    pageBuilder: (ctx, _, __) {
      return ImageGalleryViewer(
        imageUrls: imageUrls,
        initialIndex: index,
        onSaveIndex: onSaveIndex,
      );
    },
  );
}

class ImageGalleryViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final Future<void> Function(int index) onSaveIndex;

  const ImageGalleryViewer({
    super.key,
    required this.imageUrls,
    required this.initialIndex,
    required this.onSaveIndex,
  });

  @override
  State<ImageGalleryViewer> createState() => _ImageGalleryViewerState();
}

class _ImageGalleryViewerState extends State<ImageGalleryViewer> {
  late final PageController _controller;
  late int _index;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      await widget.onSaveIndex(_index);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;
    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    total > 1 ? '${_index + 1} / $total' : '预览',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: total,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (_, i) {
                      return InteractiveViewer(
                        child: Center(
                          child: RetryableNetworkImage(
                            imageUrl: widget.imageUrls[i],
                            fit: BoxFit.contain,
                            darkErrorStyle: true,
                          ),
                        ),
                      );
                    },
                  ),
                  if (total > 1) ...[
                    Positioned(
                      left: 4,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                        onPressed: _index > 0
                            ? () => _controller.previousPage(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                )
                            : null,
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      child: IconButton(
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black45,
                        ),
                        onPressed: _index < total - 1
                            ? () => _controller.nextPage(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                )
                            : null,
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: StickerButton(
                text: _saving ? '保存中...' : '保存到手机',
                icon: Icons.save_alt,
                isLoading: _saving,
                onPressed: _saving ? null : _onSave,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
