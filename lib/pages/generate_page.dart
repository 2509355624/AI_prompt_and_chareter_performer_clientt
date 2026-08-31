import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/generate_job.dart';
import '../providers/generate_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../utils/gallery_saver.dart';
import '../utils/image_bytes_cache.dart';
import '../utils/sticker_frame.dart';
import '../widgets/framed_network_image.dart';
import '../widgets/generate_config_sheet.dart';
import '../widgets/image_gallery_viewer.dart';
import '../widgets/sticker_widgets.dart';

/// ComfyUI 图片生成页（键盘收起 + 大图换页 + 任务恢复）
class GeneratePage extends StatefulWidget {
  const GeneratePage({super.key});

  @override
  State<GeneratePage> createState() => _GeneratePageState();
}

class _GeneratePageState extends State<GeneratePage>
    with WidgetsBindingObserver {
  static const int maxCount = 10;

  final _sceneController = TextEditingController();
  final _sceneFocus = FocusNode();
  int _count = 1;
  String _mode = 'manual';
  bool _savingImage = false;
  /// 预览默认带小红书边框；保存时可另选原图/边框
  bool _previewWithFrame = true;
  final Set<int> _selected = {};

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
    setState(() => _selected.clear());
    final gen = context.read<GenerateProvider>();
    await gen.startGenerate(
      scene: scene,
      count: _count.clamp(1, maxCount),
      mode: _mode,
    );
    if (!mounted) return;
    final err = gen.lastError;
    if (err != null && err.isNotEmpty && !gen.isGenerating) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err)),
      );
    }
  }

  Future<void> _saveImage(String imageUrl, {required bool withFrame}) async {
    _dismissKeyboard();
    setState(() => _savingImage = true);
    try {
      final url = _resolveUrl(imageUrl);
      var bytes = await ImageBytesCache.getRaw(url);
      if (withFrame) {
        const frameKeySuffix = '|frame|full';
        final frameKey = '$url$frameKeySuffix';
        final cached = ImageBytesCache.peekFramed(frameKey);
        if (cached != null) {
          bytes = cached;
        } else {
          bytes = await renderStickerPng(
            bytes,
            options: const StickerFrameOptions.paperCollage(),
          );
          ImageBytesCache.putFramed(frameKey, bytes);
        }
      }
      await saveImageBytesToGallery(
        bytes,
        name:
            'comfy_${withFrame ? 'frame_' : ''}${DateTime.now().millisecondsSinceEpoch}',
      );
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  Future<String?> _askSaveStyle() async {
    _dismissKeyboard();
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '保存到手机',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '预览默认是贴纸边框；保存可另选原图或边框。',
                  style: TextStyle(fontSize: 12, color: AppTheme.text2),
                ),
                const SizedBox(height: 12),
                StickerButton(
                  text: '普通保存（原图）',
                  icon: Icons.image_outlined,
                  isPrimary: false,
                  onPressed: () => Navigator.pop(ctx, 'plain'),
                ),
                const SizedBox(height: 8),
                StickerButton(
                  text: '边框保存（小红书贴纸）',
                  icon: Icons.auto_awesome,
                  onPressed: () => Navigator.pop(ctx, 'frame'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _promptSave(String imageUrl) async {
    final choice = await _askSaveStyle();
    if (choice == null || !mounted) return;
    try {
      await _saveImage(imageUrl, withFrame: choice == 'frame');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(choice == 'frame' ? '已保存边框图到相册' : '已保存原图到相册'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<void> _saveSelected(List<GenerateResultImage> results) async {
    final indexes = _selected.toList()..sort();
    if (indexes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选中要保存的图片')),
      );
      return;
    }
    final choice = await _askSaveStyle();
    if (choice == null || !mounted) return;
    final withFrame = choice == 'frame';
    setState(() => _savingImage = true);
    var ok = 0;
    try {
      for (final i in indexes) {
        if (i < 0 || i >= results.length) continue;
        await _saveImage(results[i].url, withFrame: withFrame);
        ok++;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 $ok 张到相册')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量保存中断（已成功 $ok 张）：$e')),
      );
    } finally {
      if (mounted) setState(() => _savingImage = false);
    }
  }

  Future<void> _copyPrompt(String prompt) async {
    final text = prompt.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这张没有提示词')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('提示词已复制')),
    );
  }

  void _showPromptSheet(GenerateResultImage item, int index) {
    _dismissKeyboard();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final prompt =
            item.prompt.trim().isEmpty ? '（无提示词）' : item.prompt.trim();
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              16 + MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '第 ${index + 1} 张提示词',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.45,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      prompt,
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StickerButton(
                  text: '复制提示词',
                  icon: Icons.copy,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _copyPrompt(item.prompt);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openGallery(List<GenerateResultImage> results, int index) {
    _dismissKeyboard();
    if (results.isEmpty) return;
    showImageGallery(
      context,
      imageUrls: results.map((e) => _resolveUrl(e.url)).toList(),
      prompts: results.map((e) => e.prompt).toList(),
      initialIndex: index,
      framedPreview: _previewWithFrame,
      onSaveIndex: (i) => _promptSave(results[i].url),
      onCopyPromptIndex: (i) => _copyPrompt(results[i].prompt),
    );
  }

  void _toggleSelect(int index, int total) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
      } else {
        _selected.add(index);
      }
      _selected.removeWhere((i) => i < 0 || i >= total);
    });
  }

  void _selectAll(int total) {
    setState(() {
      _selected
        ..clear()
        ..addAll(List.generate(total, (i) => i));
    });
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
            IconButton(
              tooltip: '预设配置',
              onPressed: () {
                _dismissKeyboard();
                showGenerateConfigSheet(context);
              },
              icon: const Icon(Icons.tune),
            ),
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
                  final results =
                      gen.currentJob?.results ?? const <GenerateResultImage>[];
                  if (results.isEmpty && !gen.isGenerating) {
                    return _buildEmpty();
                  }
                  return Column(
                    children: [
                      if (gen.isGenerating) _buildProgress(gen.currentJob),
                      if (results.isNotEmpty) _buildBatchBar(results),
                      Expanded(
                        child: results.length <= 1
                            ? _buildSingle(results)
                            : _buildGrid(results),
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

  Widget _buildBatchBar(List<GenerateResultImage> results) {
    final n = results.length;
    final selectedCount = _selected.where((i) => i >= 0 && i < n).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Text(
            '已选 $selectedCount/$n',
            style: const TextStyle(fontSize: 12, color: AppTheme.text2),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              _dismissKeyboard();
              _selectAll(n);
            },
            child: const Text('全选', style: TextStyle(fontSize: 12)),
          ),
          TextButton(
            onPressed: () {
              _dismissKeyboard();
              setState(() => _selected.clear());
            },
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
          StickerButton(
            text: _savingImage ? '保存中…' : '保存选中',
            icon: Icons.download,
            fontSize: 12,
            isLoading: _savingImage,
            onPressed: _savingImage ? null : () => _saveSelected(results),
          ),
        ],
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
              return Row(
                children: [
                  const Expanded(
                    child: Text(
                      '加载预设中...',
                      style: TextStyle(color: AppTheme.textMute),
                    ),
                  ),
                  _configChip(),
                ],
              );
            }
            return Row(
              children: [
                Expanded(
                  child: ListView.separated(
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
                            border:
                                Border.all(color: AppTheme.textColor, width: 2),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow:
                                selected ? AppTheme.stickerShadowSm : null,
                          ),
                          child: Center(
                            child: Text(
                              preset.name,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : AppTheme.textColor,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                _configChip(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _configChip() {
    return GestureDetector(
      onTap: () {
        _dismissKeyboard();
        showGenerateConfigSheet(context);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.textColor, width: 2),
          borderRadius: BorderRadius.circular(999),
          boxShadow: AppTheme.stickerShadowSm,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune, size: 16, color: AppTheme.textColor),
            SizedBox(width: 4),
            Text(
              '配置',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
          ],
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
              '选好预设后，在下方输入场景\n然后点「生成」\n预览默认贴纸边框，保存可选原图/边框',
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

  Widget _buildPromptMeta(GenerateResultImage item, int index) {
    final has = item.prompt.trim().isNotEmpty;
    final preview = has
        ? (item.prompt.length > 48
            ? '${item.prompt.substring(0, 48)}…'
            : item.prompt)
        : '（无提示词）';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.text2),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _showPromptSheet(item, index),
            child: const Text('查看', style: TextStyle(fontSize: 11)),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () => _copyPrompt(item.prompt),
            child: const Text('复制', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildSingle(List<GenerateResultImage> results) {
    if (results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final item = results.first;
    final selected = _selected.contains(0);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: StickerCard(
              padding: EdgeInsets.zero,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () => _openGallery(results, 0),
                    onLongPress: () => _toggleSelect(0, results.length),
                    child: ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusLg - 2),
                      child: FramedNetworkImage(
                        imageUrl: _resolveUrl(item.url),
                        showFrame: _previewWithFrame,
                        fit: BoxFit.contain,
                        onTap: () => _openGallery(results, 0),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    top: 10,
                    child: _checkBadge(selected, () {
                      _toggleSelect(0, results.length);
                    }),
                  ),
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: StickerButton(
                      text: _savingImage ? '处理中…' : '保存到手机',
                      icon: Icons.save_alt,
                      fontSize: 12,
                      isLoading: _savingImage,
                      onPressed:
                          _savingImage ? null : () => _promptSave(item.url),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _buildPromptMeta(item, 0),
        ],
      ),
    );
  }

  Widget _buildGrid(List<GenerateResultImage> results) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.58,
        ),
        itemCount: results.length,
        itemBuilder: (_, i) {
          final item = results[i];
          final selected = _selected.contains(i);
          return StickerCard(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: FramedNetworkImage(
                          imageUrl: _resolveUrl(item.url),
                          showFrame: _previewWithFrame,
                          fit: BoxFit.cover,
                          onTap: () => _openGallery(results, i),
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: _checkBadge(selected, () {
                          _toggleSelect(i, results.length);
                        }),
                      ),
                    ],
                  ),
                ),
                _buildPromptMeta(item, i),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _checkBadge(bool selected, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _dismissKeyboard();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
                            color: selected
                                ? AppTheme.accent
                                : Colors.white.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.textColor, width: 2),
          ),
          child: Icon(
            selected ? Icons.check : Icons.circle_outlined,
            size: 16,
            color: selected ? Colors.white : AppTheme.text2,
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    final showCount = _mode == 'ai';
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
                const SizedBox(width: 8),
                _modeChip(
                  _previewWithFrame ? '预览·边框' : '预览·原图',
                  _previewWithFrame,
                  () {
                    _dismissKeyboard();
                    setState(() => _previewWithFrame = !_previewWithFrame);
                  },
                ),
                if (showCount) ...[
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
                    onPressed: _count < maxCount
                        ? () {
                            _dismissKeyboard();
                            setState(() => _count++);
                          }
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    color: AppTheme.text2,
                  ),
                ],
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
                    hintText: _mode == 'ai'
                        ? '输入场景描述…（最多 $maxCount 张）'
                        : '粘贴手动 Prompt，多条用 --- 分隔',
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
