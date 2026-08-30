import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../widgets/sticker_widgets.dart';

/// 服务器配置页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _urlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _baseUrlController = TextEditingController();
  String _selectedProvider = 'deepseek';
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlController.text = settings.serverUrl;
    _apiKeyController.text = settings.apiKey;
    _modelController.text = settings.aiModel;
    _baseUrlController.text = settings.aiBaseUrl;
    _selectedProvider = settings.aiProvider;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() => _isTesting = true);
    final settings = context.read<SettingsProvider>();
    final ok = await settings.testConnection(_urlController.text.trim());
    setState(() => _isTesting = false);

    if (ok) {
      await settings.setServerUrl(_urlController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接成功！')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('连接失败，请检查地址和网络')),
        );
      }
    }
  }

  void _saveAiConfig() {
    final settings = context.read<SettingsProvider>();
    settings.setAiConfig(
      provider: _selectedProvider,
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI 配置已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.shell,
      appBar: AppBar(
        title: const Text('⚙️ 设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 服务器连接
            StickerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🌐 服务器地址',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text(
                    '你电脑上 Node.js 服务的局域网地址',
                    style: TextStyle(color: AppTheme.text2, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  StickerInput(
                    controller: _urlController,
                    hintText: 'http://192.168.x.x:3000',
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: StickerButton(
                          text: _isTesting ? '连接中...' : '测试并保存',
                          icon: Icons.wifi,
                          onPressed: _isTesting ? null : _testConnection,
                          isLoading: _isTesting,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Consumer<SettingsProvider>(
                    builder: (_, s, __) => s.isConnected
                        ? StatusBadge.ok('已连接')
                        : StatusBadge.error('未连接'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // AI Provider
            StickerCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🤖 AI 对话配置',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  // Provider 选择
                  const Text('Provider',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _providerChip('deepseek', 'DeepSeek'),
                      _providerChip('doubao', '豆包'),
                      _providerChip('ollama', '本地 Ollama'),
                      _providerChip('openai', 'OpenAI 兼容'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text('API Key',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  StickerInput(
                    controller: _apiKeyController,
                    hintText: '输入 API Key',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  const Text('模型名称',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  StickerInput(
                    controller: _modelController,
                    hintText: '如 deepseek-chat',
                  ),
                  const SizedBox(height: 12),
                  const Text('Base URL',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  StickerInput(
                    controller: _baseUrlController,
                    hintText: '可选，自定义 API 地址',
                  ),
                  const SizedBox(height: 12),
                  StickerButton(
                    text: '保存 AI 配置',
                    icon: Icons.save,
                    onPressed: _saveAiConfig,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Center(
              child: Text(
                'Console UI Master · v0.1',
                style: TextStyle(color: AppTheme.textMute, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _providerChip(String value, String label) {
    final selected = _selectedProvider == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _selectedProvider = value);
      },
      selectedColor: AppTheme.accentSoft,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppTheme.textColor, width: 2),
      labelStyle: TextStyle(
        color: selected ? AppTheme.accent : AppTheme.textColor,
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
