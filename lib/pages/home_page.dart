import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../widgets/sticker_widgets.dart';
import 'character_list_page.dart';
import 'chat_page.dart';
import 'generate_page.dart';
import 'settings_page.dart';
import '../models/character.dart';

/// 工具中心首页：竖排卡片，对齐 Web 端入口。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.shell,
      appBar: AppBar(
        title: const Text('✨ AI 工具中心'),
        actions: [
          IconButton(
            tooltip: '服务器设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Consumer<SettingsProvider>(
            builder: (_, s, __) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: s.isConnected
                  ? StatusBadge.ok('已连接 ${s.serverUrl}')
                  : StatusBadge.error('未连接 · 点右上角设置填局域网地址'),
            ),
          ),
          const Text(
            '贴纸手帐风入口 · 选一个工具开始',
            style: TextStyle(color: AppTheme.text2, fontSize: 13),
          ),
          const SizedBox(height: 14),
          _ToolCard(
            emoji: '🎭',
            title: 'AI 角色扮演',
            desc: '自定义角色对白与出图，沉浸式聊天联动分镜。',
            tilt: -0.5,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _RoleplayFlow()),
              );
            },
          ),
          const SizedBox(height: 14),
          _ToolCard(
            emoji: '✨',
            title: 'ComfyUI 图片生成',
            desc: '角色预设批量出图，AI 扩写，默认贴纸边框预览导出。',
            tilt: 0.4,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const GeneratePage()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String desc;
  final double tilt;
  final VoidCallback onTap;

  const _ToolCard({
    required this.emoji,
    required this.title,
    required this.desc,
    required this.tilt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt * 0.0174533,
      child: StickerCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Text(
                  '打开 →',
                  style: TextStyle(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              style: const TextStyle(color: AppTheme.text2, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// 角色列表 → 聊天
class _RoleplayFlow extends StatefulWidget {
  const _RoleplayFlow();

  @override
  State<_RoleplayFlow> createState() => _RoleplayFlowState();
}

class _RoleplayFlowState extends State<_RoleplayFlow> {
  Character? _selected;

  @override
  Widget build(BuildContext context) {
    if (_selected != null) {
      return ChatPage(
        character: _selected!,
        onBackToList: () => setState(() => _selected = null),
      );
    }
    return CharacterListPage(
      onCharacterSelected: (c) => setState(() => _selected = c),
    );
  }
}
