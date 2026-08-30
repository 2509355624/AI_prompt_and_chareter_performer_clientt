import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/settings_provider.dart';
import '../models/character.dart';
import 'generate_page.dart';
import 'character_list_page.dart';
import 'chat_page.dart';
import 'settings_page.dart';

/// 首页 - 底部 Tab 导航
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const GeneratePage(),
    const _CharacterEntry(),
    const SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          border: const Border(
            top: BorderSide(color: AppTheme.textColor, width: 2),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.auto_awesome, '生成'),
                _buildNavItem(1, Icons.face_outlined, '角色'),
                _buildNavItem(2, Icons.settings_outlined, '设置'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final selected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected ? AppTheme.accent : AppTheme.textMute,
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? AppTheme.accent : AppTheme.textMute,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 角色入口 - 先显示列表，选中后进入对话页
class _CharacterEntry extends StatefulWidget {
  const _CharacterEntry();

  @override
  State<_CharacterEntry> createState() => _CharacterEntryState();
}

class _CharacterEntryState extends State<_CharacterEntry> {
  Character? _selectedCharacter;

  @override
  Widget build(BuildContext context) {
    if (_selectedCharacter != null) {
      return ChatPage(
        character: _selectedCharacter!,
      );
    }

    return CharacterListPage(
      onCharacterSelected: (char) {
        setState(() => _selectedCharacter = char);
      },
    );
  }
}
