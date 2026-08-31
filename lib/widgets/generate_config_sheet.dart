import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/preset.dart';
import '../providers/generate_provider.dart';
import '../theme/app_theme.dart';
import 'sticker_widgets.dart';

Future<void> showGenerateConfigSheet(BuildContext context) async {
  final gen = context.read<GenerateProvider>();
  await gen.loadConfigOptions();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => const GenerateConfigSheet(),
  );
}

/// Comfy 预设配置卡片（对齐 Web 右侧面板，手机端用底部抽屉）
class GenerateConfigSheet extends StatefulWidget {
  const GenerateConfigSheet({super.key});

  @override
  State<GenerateConfigSheet> createState() => _GenerateConfigSheetState();
}

class _GenerateConfigSheetState extends State<GenerateConfigSheet> {
  late TextEditingController _name;
  late TextEditingController _basePrompt;
  late TextEditingController _negative;
  late TextEditingController _width;
  late TextEditingController _height;
  late TextEditingController _steps;
  late TextEditingController _cfg;
  late TextEditingController _aiSystem;
  late TextEditingController _aiUser;
  final List<TextEditingController> _loraStr = [];

  String _checkpoint = '';
  String _sampler = 'euler';
  String _scheduler = 'simple';
  String _upscaleModel = '';
  bool _enableHires = false;
  bool _enableUpscale = false;
  final List<String> _loraPick = ['(none)', '(none)', '(none)'];
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _basePrompt = TextEditingController();
    _negative = TextEditingController();
    _width = TextEditingController();
    _height = TextEditingController();
    _steps = TextEditingController();
    _cfg = TextEditingController();
    _aiSystem = TextEditingController();
    _aiUser = TextEditingController();
    for (var i = 0; i < 3; i++) {
      _loraStr.add(TextEditingController(text: '1'));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _hydrateFromProvider());
  }

  @override
  void dispose() {
    _name.dispose();
    _basePrompt.dispose();
    _negative.dispose();
    _width.dispose();
    _height.dispose();
    _steps.dispose();
    _cfg.dispose();
    _aiSystem.dispose();
    _aiUser.dispose();
    for (final c in _loraStr) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrateFromProvider() {
    final gen = context.read<GenerateProvider>();
    final p = gen.draft;
    if (p == null) return;
    _name.text = p.name;
    _basePrompt.text = p.basePrompt;
    _negative.text = p.negativePrompt;
    _width.text = '${p.width}';
    _height.text = '${p.height}';
    _steps.text = '${p.steps}';
    _cfg.text = p.cfg.toString();
    _checkpoint = p.checkpointName.isNotEmpty
        ? p.checkpointName
        : p.unetName;
    _sampler = p.sampler;
    _scheduler = p.scheduler;
    _upscaleModel = p.upscaleModel;
    _enableHires = p.enableHires && !p.isKrea2;
    _enableUpscale = p.enableUpscale;
    for (var i = 0; i < 3; i++) {
      final l = i < p.loras.length ? p.loras[i] : null;
      _loraPick[i] =
          (l == null || l.name.isEmpty) ? '(none)' : l.name;
      _loraStr[i].text = (l?.strengthModel ?? 0).toString();
    }
    _aiSystem.text = gen.expandSettings.clothingExpandSystem;
    _aiUser.text = gen.expandSettings.clothingExpandUserTemplate;
    _hydrated = true;
    setState(() {});
  }

  List<LoraConfig> _buildLoras({required bool krea2}) {
    LoraConfig at(int i) {
      final name = _loraPick[i];
      final str = double.tryParse(_loraStr[i].text.trim()) ?? 0;
      return LoraConfig(
        name: name.isEmpty ? '(none)' : name,
        strengthModel: str,
        strengthClip: 1,
      );
    }

    if (krea2) {
      return [
        at(0),
        const LoraConfig(name: '(none)', strengthModel: 0, strengthClip: 0),
        const LoraConfig(name: '(none)', strengthModel: 0, strengthClip: 0),
      ];
    }
    return [at(0), at(1), at(2)];
  }

  GeneratePreset _buildDraft(GenerateProvider gen) {
    final prev = gen.draft;
    final ckpt = _checkpoint;
    final isKrea2 = prev?.isKrea2 == true ||
        ckpt.toLowerCase().endsWith('.gguf') ||
        _name.text.toLowerCase().contains('krea2');
    return GeneratePreset(
      id: prev?.id ?? '',
      name: _name.text.trim().isEmpty ? '未命名预设' : _name.text.trim(),
      workflowEngine: isKrea2 ? 'krea2' : (prev?.workflowEngine ?? 'sdxl'),
      basePrompt: _basePrompt.text,
      negativePrompt: _negative.text,
      width: int.tryParse(_width.text.trim()) ?? 832,
      height: int.tryParse(_height.text.trim()) ?? 1216,
      steps: int.tryParse(_steps.text.trim()) ?? 6,
      cfg: double.tryParse(_cfg.text.trim()) ?? 1,
      sampler: _sampler,
      scheduler: _scheduler,
      checkpointName: ckpt,
      unetName: isKrea2 ? ckpt : (prev?.unetName ?? ''),
      clipName: prev?.clipName ?? '',
      clipType: prev?.clipType ?? '',
      vaeName: prev?.vaeName ?? '',
      loras: _buildLoras(krea2: isKrea2),
      enableHires: isKrea2 ? false : _enableHires,
      hiresWidth: prev?.hiresWidth ?? 1080,
      hiresHeight: prev?.hiresHeight ?? 1920,
      enableUpscale: _enableUpscale,
      upscaleModel: _upscaleModel,
      samplerOptions: prev?.samplerOptions ?? const [],
      schedulerOptions: prev?.schedulerOptions ?? const [],
    );
  }

  void _pushDraft() {
    if (!_hydrated) return;
    final gen = context.read<GenerateProvider>();
    gen.updateDraft(_buildDraft(gen));
  }

  Future<void> _savePreset() async {
    _pushDraft();
    final gen = context.read<GenerateProvider>();
    final ok = await gen.saveDraftPreset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '预设已保存' : (gen.lastError ?? '保存失败'))),
    );
    if (ok) _hydrateFromProvider();
  }

  Future<void> _saveAi() async {
    final gen = context.read<GenerateProvider>();
    gen.updateExpandSettings(
      GenerateExpandSettings(
        clothingExpandSystem: _aiSystem.text,
        clothingExpandUserTemplate: _aiUser.text,
      ),
    );
    final ok = await gen.saveExpandSettings();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'AI 扩写提示词已保存' : (gen.lastError ?? '保存失败'))),
    );
  }

  Future<void> _deletePreset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: const Text('确定删除当前预设？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final gen = context.read<GenerateProvider>();
    final ok = await gen.deleteActivePreset();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已删除' : (gen.lastError ?? '删除失败'))),
    );
    if (ok) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final height = MediaQuery.sizeOf(context).height * 0.92;

    return Consumer<GenerateProvider>(
      builder: (context, gen, _) {
        final draft = gen.draft;
        final isKrea2 = draft?.isKrea2 == true ||
            _checkpoint.toLowerCase().endsWith('.gguf');
        final checkpoints = _ensureOption(gen.checkpoints, _checkpoint);
        final samplers = _ensureOption(gen.samplerOptions, _sampler);
        final schedulers = _ensureOption(gen.schedulerOptions, _scheduler);
        final ups = _ensureOption(gen.upscaleModels, _upscaleModel);
        final loraOpts = ['(none)', ...gen.loraNames];

        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '预设配置',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          gen.createBlankPreset();
                          _hydrateFromProvider();
                        },
                        child: const Text('新建'),
                      ),
                      IconButton(
                        onPressed: () {
                          _pushDraft();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.rule),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _label('预设名称'),
                      _field(_name, onChanged: (_) => _pushDraft()),
                      const SizedBox(height: 12),
                      _longTextBlock(
                        label: '底模 basePrompt（角色特征）',
                        controller: _basePrompt,
                        hint: '点击「编辑」修改长文本，避免滑动误触',
                        maxLines: 10,
                      ),
                      const SizedBox(height: 16),
                      _sectionTitle('AI 扩写提示词'),
                      const Text(
                        '仅「AI 扩写」模式使用；手动 Prompt 不走这里。',
                        style: TextStyle(fontSize: 12, color: AppTheme.text2),
                      ),
                      const SizedBox(height: 8),
                      _longTextBlock(
                        label: 'System',
                        controller: _aiSystem,
                        hint: '点击「编辑」打开编辑窗口',
                        maxLines: 14,
                        pushDraftOnSave: false,
                      ),
                      const SizedBox(height: 8),
                      _longTextBlock(
                        label: 'User 模板（可用 {scene} {count}）',
                        controller: _aiUser,
                        hint: '点击「编辑」打开编辑窗口',
                        maxLines: 8,
                        pushDraftOnSave: false,
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StickerButton(
                          text: '保存 AI 提示词',
                          icon: Icons.save_outlined,
                          fontSize: 12,
                          onPressed: _saveAi,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _label(isKrea2 ? 'Unet (GGUF)' : 'Checkpoint'),
                      _dropdown(
                        value: checkpoints.contains(_checkpoint)
                            ? _checkpoint
                            : (checkpoints.isEmpty ? null : checkpoints.first),
                        items: checkpoints,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _checkpoint = v);
                          _pushDraft();
                        },
                      ),
                      if (isKrea2) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Krea2：对照 Unet / 尺寸 / KSampler / LoRA1；可勾选 2× 放大。无高清修复、无 LoRA2/3。',
                          style:
                              TextStyle(fontSize: 12, color: AppTheme.text2),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('宽'),
                                _field(
                                  _width,
                                  keyboard: TextInputType.number,
                                  onChanged: (_) => _pushDraft(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('高'),
                                _field(
                                  _height,
                                  keyboard: TextInputType.number,
                                  onChanged: (_) => _pushDraft(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('Steps'),
                                _field(
                                  _steps,
                                  keyboard: TextInputType.number,
                                  onChanged: (_) => _pushDraft(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _label('CFG'),
                                _field(
                                  _cfg,
                                  keyboard:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  onChanged: (_) => _pushDraft(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _label('Sampler'),
                      _dropdown(
                        value: samplers.contains(_sampler)
                            ? _sampler
                            : samplers.first,
                        items: samplers,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _sampler = v);
                          _pushDraft();
                        },
                      ),
                      const SizedBox(height: 12),
                      _label('Scheduler'),
                      _dropdown(
                        value: schedulers.contains(_scheduler)
                            ? _scheduler
                            : schedulers.first,
                        items: schedulers,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _scheduler = v);
                          _pushDraft();
                        },
                      ),
                      const SizedBox(height: 12),
                      _longTextBlock(
                        label: 'Negative',
                        controller: _negative,
                        hint: '点击「编辑」修改负向提示词',
                        maxLines: 8,
                      ),
                      if (!isKrea2) ...[
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('高清修复', style: TextStyle(fontSize: 14)),
                          value: _enableHires,
                          activeColor: AppTheme.accent,
                          onChanged: (v) {
                            setState(() => _enableHires = v);
                            _pushDraft();
                          },
                        ),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('2× 放大', style: TextStyle(fontSize: 14)),
                        subtitle: const Text(
                          '勾选后点生成即生效，不必先保存预设',
                          style: TextStyle(fontSize: 12, color: AppTheme.text2),
                        ),
                        value: _enableUpscale,
                        activeColor: AppTheme.accent,
                        onChanged: (v) {
                          setState(() => _enableUpscale = v);
                          _pushDraft();
                        },
                      ),
                      if (_enableUpscale && ups.isNotEmpty) ...[
                        _label('放大模型'),
                        _dropdown(
                          value: ups.contains(_upscaleModel)
                              ? _upscaleModel
                              : ups.first,
                          items: ups,
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() => _upscaleModel = v);
                            _pushDraft();
                          },
                        ),
                      ],
                      const SizedBox(height: 8),
                      _sectionTitle('LoRA'),
                      _loraRow(0, loraOpts),
                      if (!isKrea2) ...[
                        _loraRow(1, loraOpts),
                        _loraRow(2, loraOpts),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: StickerButton(
                              text: gen.savingPreset ? '保存中…' : '保存预设',
                              icon: Icons.save,
                              isLoading: gen.savingPreset,
                              onPressed:
                                  gen.savingPreset ? null : _savePreset,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: StickerButton(
                              text: '删除',
                              icon: Icons.delete_outline,
                              isPrimary: false,
                              onPressed: gen.activePresetId == null
                                  ? null
                                  : _deletePreset,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '改完勾选即可生成；「保存预设」才写入服务器列表。',
                        style: TextStyle(fontSize: 12, color: AppTheme.textMute),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _loraRow(int index, List<String> options) {
    final value = options.contains(_loraPick[index])
        ? _loraPick[index]
        : '(none)';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('LoRA${index + 1}'),
                _dropdown(
                  value: value,
                  items: options,
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _loraPick[index] = v);
                    _pushDraft();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _label('强度'),
                _field(
                  _loraStr[index],
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  onChanged: (_) => _pushDraft(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _ensureOption(List<String> list, String value) {
    if (value.isEmpty) return list;
    if (list.contains(value)) return list;
    return [value, ...list];
  }

  Widget _longTextBlock({
    required String label,
    required TextEditingController controller,
    required String hint,
    int maxLines = 8,
    bool pushDraftOnSave = true,
  }) {
    final text = controller.text.trim();
    final preview = text.isEmpty
        ? '（空）点编辑填写'
        : (text.length > 90 ? '${text.substring(0, 90)}…' : text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _label(label)),
            TextButton.icon(
              onPressed: () => _openLongTextEditor(
                title: label,
                controller: controller,
                maxLines: maxLines,
                pushDraftOnSave: pushDraftOnSave,
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('编辑', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        InkWell(
          onTap: () => _openLongTextEditor(
            title: label,
            controller: controller,
            maxLines: maxLines,
            pushDraftOnSave: pushDraftOnSave,
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: AppTheme.textColor, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  preview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: text.isEmpty ? AppTheme.textMute : AppTheme.textColor,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hint,
                  style: const TextStyle(fontSize: 11, color: AppTheme.textMute),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openLongTextEditor({
    required String title,
    required TextEditingController controller,
    int maxLines = 8,
    bool pushDraftOnSave = true,
  }) async {
    final draft = TextEditingController(text: controller.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(title, style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: double.maxFinite,
            child: TextField(
              controller: draft,
              maxLines: maxLines,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide:
                      const BorderSide(color: AppTheme.textColor, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  borderSide:
                      const BorderSide(color: AppTheme.textColor, width: 2),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('完成', style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      setState(() => controller.text = draft.text);
      if (pushDraftOnSave) _pushDraft();
    }
    draft.dispose();
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppTheme.textColor,
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppTheme.text2),
      ),
    );
  }

  Widget _field(
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboard,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 14, color: AppTheme.textColor),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.textColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.textColor, width: 2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.accent, width: 2),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    final safeItems = items.isEmpty && value != null ? [value] : items;
    return DropdownButtonFormField<String>(
      value: value != null && safeItems.contains(value) ? value : null,
      isExpanded: true,
      items: safeItems
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(
                e,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: AppTheme.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.textColor, width: 2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          borderSide: const BorderSide(color: AppTheme.textColor, width: 2),
        ),
      ),
    );
  }
}
