import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../widgets/sticker_widgets.dart';

/// 设置：只配局域网 Node 地址。密钥在电脑 .env。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _urlController = TextEditingController();
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _urlController.text = settings.serverUrl.isEmpty
        ? SettingsProvider.defaultServerUrl
        : settings.serverUrl;
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    setState(() => _testing = true);
    final ok = await context.read<SettingsProvider>().testAndSave(
          _urlController.text,
        );
    setState(() => _testing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '连接成功，已保存' : '连接失败：检查电脑 Node 是否启动、防火墙、是否同一 Wi‑Fi'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.shell,
      appBar: AppBar(title: const Text('⚙️ 设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StickerCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🌐 服务器地址',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '填你电脑的局域网 IP（ipconfig 里 WLAN 的 IPv4）。\n'
                  'API Key / 模型 / Comfy 地址全部在电脑服务端 .env，手机不存密钥。',
                  style: TextStyle(color: AppTheme.text2, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                StickerInput(
                  controller: _urlController,
                  hintText: 'http://192.168.0.128:3000',
                ),
                const SizedBox(height: 12),
                StickerButton(
                  text: _testing ? '测试中…' : '测试并保存',
                  icon: Icons.wifi_tethering,
                  onPressed: _testing ? null : _testAndSave,
                  isLoading: _testing,
                ),
                const SizedBox(height: 10),
                Consumer<SettingsProvider>(
                  builder: (_, s, __) => s.isConnected
                      ? StatusBadge.ok('已连接 ${s.serverUrl}')
                      : StatusBadge.error('未连接'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            '提示：手机与电脑须同一 Wi‑Fi；电脑防火墙放行 3000 端口。',
            style: TextStyle(color: AppTheme.textMute, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
