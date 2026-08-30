import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/generate_job.dart';
import '../providers/generate_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/gallery_saver.dart';
import '../widgets/image_gallery_viewer.dart';
import '../widgets/retryable_network_image.dart';
import '../widgets/sticker_widgets.dart';

/// ComfyUI 图片生成页（键盘收起 + 大图换页 + 任务恢复）
class GeneratePage extends StatefulWidget {
  const GeneratePage({super.key});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage>
    with WidgetsBindingObserver {
  final _sceneController = TextEditingController();
  final _sceneFocus = FocusNode();
  int _count = 1;
  String _mode = 'manual';
  bool _savingImage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final gen = context.read<GenerateProvider>();
      gen.loadPresets();
      gen.resumeIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sceneController.dispose();
    _sceneFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<GenerateProvider>().resumeIfNeeded();
    }
  }

  void _dismissKeyboard() {
    _sceneFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  String _resolveUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${context.read<SettingsProvider>().serverUrl}$url';
  }

  Future<void> _startGenerate() async {
    _dismissKeyboard();
    final scene = _sceneController.text.trim();
    if (scene.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入场景描述')),
      );
      return;
    }
    await context.read<GenerateProvider>().startGenerate(
          scene: scene,
          count: _count,
          mode: _mode,
        );
  }

  Future<void> _saveImage(String imageUrl) async {
    _dismissKeyboard();
    setState(() => _savingImage = true);
    try {
      final response = await Dio().get(
        _resolveUrl(imageUrl),
        options: Options(responseType: ResponseType.bytes),
      );
      await saveImageBytesToGallery(
        Uint8List.fromList(response.data as List<int>),
        name: 'comfy_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存到相册')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  void _openGallery(List<String> images, int index) {
    _dismissKeyboard();
    if (images.isEmpty) return;
    showImageGallery(
      context,
      imageUrls: images.map(_resolveUrl).toList(),
      initialIndex: index,
      onSaveIndex: (i) => _saveImage(images[i]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: AppTheme.shell,
        appBar: AppBar(
          title: const Text('✨ 图片生成'),
          actions: [
            Consumer<GenerateProvider>(
              builder: (_, gen, __) {
                if (!gen.isGenerating) return const SizedBox.shrink();
                return TextButton(
                  onPressed: () {
                    _dismissKeyboard();
                    gen.cancelCurrent();
                  },
                  child: const Text(
                    '取消',
                    style: TextStyle(color: AppTheme.accent),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            _buildPresetBar(),
            Expanded(
              child: Consumer<GenerateProvider>(
                builder: (_, gen, __) {
                  final images = gen.currentJob?.images ?? const <String>[];
                  if (images.isEmpty && !gen.isGenerating) {
                    return _buildEmpty();
                  }
                  return Column(
                    children: [
                      if (gen.isGenerating) _buildProgress(gen.currentJob),
                      Expanded(
                        child: images.length <= 1
                            ? _buildSingle(images)
                            : _buildGrid(images),
                      ),
                    ],
                  );
                },
              ),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetBar() {
    return SizedBox(
      height: 60,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Consumer<GenerateProvider>(
          builder: (_, gen, __) {
            if (gen.presets.isEmpty) {
              return const Center(
                child: Text(
                  '加载预设中...',
                  style: TextStyle(color: AppTheme.textMute),
                ),
              );
            }
            return ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: gen.presets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final preset = gen.presets[i];
                final selected = gen.activePresetId == preset.id;
                return GestureDetector(
                  onTap: () {
                    _dismissKeyboard();
                    gen.selectPreset(preset.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.accent : AppTheme.card,
                      border: Border.all(color: AppTheme.textColor, width: 2),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: selected ? AppTheme.stickerShadowSm : null,
                    ),
                    child: Center(
                      child: Text(
                        preset.name,
                        style: TextStyle(
                          color: selected ? Colors.white : AppTheme.textColor,
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 64, color: AppTheme.textMute),
            SizedBox(height: 16),
            Text(
              '选好预设后，在下方输入场景\n然后点「生成」',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.text2, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress(GenerateJob? job) {
    final prompt = job?.currentPrompt;
    final label = (prompt != null && prompt.isNotEmpty)
        ? '生成中：${prompt.length > 30 ? '${prompt.substring(0, 30)}...' : prompt}'
        : '生成中...';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppTheme.text2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${job?.doneCount ?? 0}/${job?.totalCount ?? 0}',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingle(List<String> images) {
    if (images.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final url = images.first;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StickerCard(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => _openGallery(images, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
                child: RetryableNetworkImage(
                  imageUrl: _resolveUrl(url),
                  fit: BoxFit.contain,
                  onTap: () => _openGallery(images, 0),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: StickerButton(
                text: _savingImage ? '保存中...' : '保存到手机',
                icon: Icons.save_alt,
                fontSize: 12,
                isLoading: _savingImage,
                onPressed: _savingImage ? null : () => _saveImage(url),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<String> images) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.7,
        ),
        itemCount: images.length,
        itemBuilder: (_, i) {
          final url = images[i];
          return ClipRRect(
            borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
            child: StickerCard(
              padding: EdgeInsets.zero,
              child: RetryableNetworkImage(
                imageUrl: _resolveUrl(url),
                fit: BoxFit.cover,
                onTap: () => _openGallery(images, i),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.rule, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _modeChip('AI 扩写', _mode == 'ai', () {
                  _dismissKeyboard();
                  setState(() => _mode = 'ai');
                }),
                const SizedBox(width: 8),
                _modeChip('手动', _mode == 'manual', () {
                  _dismissKeyboard();
                  setState(() => _mode = 'manual');
                }),
                const Spacer(),
                const Text('数量：', style: TextStyle(fontSize: 13)),
                IconButton(
                  onPressed: _count > 1
                      ? () {
                          _dismissKeyboard();
                          setState(() => _count--);
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppTheme.text2,
                ),
                Text(
                  '$_count',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: _count < 30
                      ? () {
                          _dismissKeyboard();
                          setState(() => _count++);
                        }
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppTheme.text2,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: StickerInput(
                    controller: _sceneController,
                    focusNode: _sceneFocus,
                    hintText: '输入场景描述...',
                    maxLines: 2,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _startGenerate(),
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<GenerateProvider>(
                  builder: (_, gen, __) => StickerButton(
                    text: gen.isGenerating ? '生成中' : '生成',
                    icon: Icons.auto_awesome,
                    isLoading: gen.isGenerating,
                    onPressed: gen.isGenerating ? null : _startGenerate,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentSoft : Colors.white,
          border: Border.all(color: AppTheme.textColor, width: 2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? AppTheme.accent : AppTheme.textColor,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
