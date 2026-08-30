import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'dart:typed_data';
import '../theme/app_theme.dart';
import '../providers/generate_provider.dart';
import '../providers/settings_provider.dart';
import '../models/generate_job.dart';
import '../widgets/sticker_widgets.dart';
import '../utils/gallery_saver.dart';

/// ComfyUI 图片生成页
class GeneratePage extends StatefulWidget {
  const GeneratePage({super.key});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage> {
  final _sceneController = TextEditingController();
  int _count = 1;
  String _mode = 'manual'; // ai / manual
  int _selectedImageIndex = 0;
  bool _savingImage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GenerateProvider>().loadPresets();
    });
  }

  @override
  void dispose() {
    _sceneController.dispose();
    super.dispose();
  }

  Future<void> _startGenerate() async {
    final scene = _sceneController.text.trim();
    if (scene.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入场景描述')),
      );
      return;
    }
    final gen = context.read<GenerateProvider>();
    await gen.startGenerate(
      scene: scene,
      count: _count,
      mode: _mode,
    );
  }

  Future<void> _saveImage(String imageUrl) async {
    setState(() => _savingImage = true);
    try {
      final settings = context.read<SettingsProvider>();
      final fullUrl = imageUrl.startsWith('http')
          ? imageUrl
          : '${settings.serverUrl}$imageUrl';

      final response = await Dio().get(
        fullUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = Uint8List.fromList(response.data);

      await saveImageBytesToGallery(
        bytes,
        name: 'comfy_${DateTime.now().millisecondsSinceEpoch}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
    setState(() => _savingImage = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.shell,
      appBar: AppBar(
        title: const Text('✨ 图片生成'),
        actions: [
          Consumer<GenerateProvider>(
            builder: (_, gen, __) => gen.isGenerating
                ? Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: TextButton(
                      onPressed: () => gen.cancelCurrent(),
                      child: const Text(
                        '取消',
                        style: TextStyle(color: AppTheme.accent),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          // 预设选择条
          _buildPresetBar(),
          // 主内容区
          Expanded(
            child: Consumer<GenerateProvider>(
              builder: (_, gen, __) {
                final job = gen.currentJob;
                final images = job?.images ?? [];

                if (images.isEmpty && !gen.isGenerating) {
                  return _buildEmptyState();
                }

                return Column(
                  children: [
                    // 进度条
                    if (gen.isGenerating) _buildProgressBar(job),
                    // 图片展示
                    Expanded(
                      child: images.length == 1
                          ? _buildSingleImage(images.first)
                          : _buildImageGrid(images),
                    ),
                  ],
                );
              },
            ),
          ),
          // 底部输入区
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildPresetBar() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Consumer<GenerateProvider>(
        builder: (_, gen, __) {
          if (gen.presets.isEmpty) {
            return const Center(
              child: Text('加载预设中...',
                  style: TextStyle(color: AppTheme.textMute)),
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
                onTap: () => gen.selectPreset(preset.id),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.accent : AppTheme.card,
                    border:
                        Border.all(color: AppTheme.textColor, width: 2),
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
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_outlined, size: 64, color: AppTheme.textMute),
            SizedBox(height: 16),
            Text(
              '选好预设后，在下方输入场景\n然后点「开始生成」',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.text2, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(GenerateJob? job) {
    return Container(
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
              job?.currentPrompt != null
                  ? '生成中：${job!.currentPrompt!.length > 30 ? '${job.currentPrompt!.substring(0, 30)}...' : job.currentPrompt}'
                  : '生成中...',
              style: const TextStyle(fontSize: 12, color: AppTheme.text2),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${job?.doneCount ?? 0}/${job?.totalCount ?? 0}',
            style: const TextStyle(
                fontSize: 12,
                color: AppTheme.accent,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleImage(String url) {
    final settings = context.read<SettingsProvider>();
    final fullUrl =
        url.startsWith('http') ? url : '${settings.serverUrl}$url';

    return Padding(
      padding: const EdgeInsets.all(16),
      child: StickerCard(
        padding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusLg - 2),
              child: CachedNetworkImage(
                imageUrl: fullUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (_, __, ___) => const Icon(Icons.broken_image),
              ),
            ),
            Positioned(
              bottom: 12,
              right: 12,
              child: StickerButton(
                text: _savingImage ? '保存中...' : '保存到手机',
                icon: Icons.save_alt,
                onPressed: _savingImage ? null : () => _saveImage(url),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageGrid(List<String> images) {
    final settings = context.read<SettingsProvider>();
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
          final fullUrl =
              url.startsWith('http') ? url : '${settings.serverUrl}$url';
          return GestureDetector(
            onTap: () {
              setState(() => _selectedImageIndex = i);
              _showImageDialog(url);
            },
            child: StickerCard(
              padding: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius:
                    BorderRadius.circular(AppTheme.radiusLg - 2),
                child: CachedNetworkImage(
                  imageUrl: fullUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: InteractiveViewer(
                child: CachedNetworkImage(
                  imageUrl: url.startsWith('http')
                      ? url
                      : '${context.read<SettingsProvider>().serverUrl}$url',
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 12),
            StickerButton(
              text: '保存到手机',
              icon: Icons.save_alt,
              onPressed: () {
                Navigator.pop(context);
                _saveImage(url);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: const Border(
          top: BorderSide(color: AppTheme.rule, width: 1),
        ),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 模式切换 + 数量
            Row(
              children: [
                _modeChip('AI 扩写', _mode == 'ai', () {
                  setState(() => _mode = 'ai');
                }),
                const SizedBox(width: 8),
                _modeChip('手动', _mode == 'manual', () {
                  setState(() => _mode = 'manual');
                }),
                const Spacer(),
                const Text('数量：', style: TextStyle(fontSize: 13)),
                IconButton(
                  onPressed: _count > 1
                      ? () => setState(() => _count--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  color: AppTheme.text2,
                ),
                Text('$_count',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  onPressed: _count < 30
                      ? () => setState(() => _count++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  color: AppTheme.text2,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 输入框 + 按钮
            Row(
              children: [
                Expanded(
                  child: StickerInput(
                    controller: _sceneController,
                    hintText: '输入场景描述...',
                    maxLines: 2,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _startGenerate(),
                  ),
                ),
                const SizedBox(width: 8),
                Consumer<GenerateProvider>(
                  builder: (_, gen, __) => StickerButton(
                    text: gen.isGenerating ? '生成中' : '生成',
                    icon: Icons.auto_awesome,
                    onPressed: gen.isGenerating ? null : _startGenerate,
                    isLoading: gen.isGenerating,
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
