import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../providers/character_provider.dart';
import '../models/character.dart';
import '../widgets/sticker_widgets.dart';

/// 角色列表页
class CharacterListPage extends StatefulWidget {
  final void Function(Character) onCharacterSelected;

  const CharacterListPage({
    super.key,
    required this.onCharacterSelected,
  });

  @override
  State<CharacterListPage> createState() => _CharacterListPageState();
}

class _CharacterListPageState extends State<CharacterListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CharacterProvider>().loadCharacters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.shell,
      appBar: AppBar(
        title: const Text('🎭 角色选择'),
      ),
      body: Consumer<CharacterProvider>(
        builder: (_, provider, __) {
          if (provider.isLoading && provider.characters.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.characters.isEmpty) {
            return const Center(
              child: Text('暂无角色', style: TextStyle(color: AppTheme.textMute)),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: provider.characters.length,
            itemBuilder: (_, i) {
              final char = provider.characters[i];
              return _CharacterCard(
                character: char,
                onTap: () => widget.onCharacterSelected(char),
              );
            },
          );
        },
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  final Character character;
  final VoidCallback onTap;

  const _CharacterCard({
    required this.character,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头像区域
          Expanded(
            flex: 3,
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppTheme.radiusLg - 2),
                ),
              ),
              child: Center(
                child: Text(
                  character.avatar,
                  style: const TextStyle(fontSize: 48),
                ),
              ),
            ),
          ),
          // 信息区域
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    character.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    character.description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.text2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
