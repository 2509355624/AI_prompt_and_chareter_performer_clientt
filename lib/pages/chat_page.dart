import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:gal/gal.dart';
import 'package:dio/dio.dart';
import 'dart:typed_data';
import '../theme/app_theme.dart';
import '../providers/character_provider.dart';
import '../providers/settings_provider.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import '../widgets/sticker_widgets.dart';

/// 对话页
class ChatPage extends StatefulWidget {
  final Character character;

  const ChatPage({super.key, required this.character});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _savingImage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CharacterProvider>();
      provider.selectCharacter(widget.character);
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final settings = context.read<SettingsProvider>();
    final provider = context.read<CharacterProvider>();

    provider.sendMessage(
      text,
      provider: settings.aiProvider,
      apiKey: settings.apiKey,
      baseUrl: settings.aiBaseUrl,
      model: settings.aiModel,
    );

    _inputController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
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

      await Gal.putImageBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册 📱')),
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
        title: Row(
          children: [
            Text(widget.character.avatar),
            const SizedBox(width: 8),
            Text(widget.character.name),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear') {
                context.read<CharacterProvider>().clearMessages();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'clear', child: Text('清空对话')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(
            child: Consumer<CharacterProvider>(
              builder: (_, provider, __) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                if (provider.messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.character.avatar,
                          style: const TextStyle(fontSize: 64),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '和${widget.character.name}打个招呼吧~',
                          style: const TextStyle(color: AppTheme.text2),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: provider.messages.length,
                  itemBuilder: (_, i) {
                    final msg = provider.messages[i];
                    return _MessageBubble(
                      message: msg,
                      character: widget.character,
                      onSaveImage: _saveImage,
                    );
                  },
                );
              },
            ),
          ),
          // 输入栏
          _buildInputBar(),
        ],
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: StickerInput(
                controller: _inputController,
                hintText: '说点什么...',
                maxLines: 4,
                textInputAction: TextInputAction.newline,
              ),
            ),
            const SizedBox(width: 8),
            Consumer<CharacterProvider>(
              builder: (_, provider, __) => Container(
                height: 48,
                child: StickerButton(
                  text: provider.isSending ? '' : '发送',
                  icon: Icons.send,
                  onPressed: provider.isSending ? null : _sendMessage,
                  isLoading: provider.isSending,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final Character character;
  final Future<void> Function(String) onSaveImage;

  const _MessageBubble({
    required this.message,
    required this.character,
    required this.onSaveImage,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // 文字气泡
                StickerCard(
                  backgroundColor:
                      isUser ? AppTheme.accent : AppTheme.card,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shadow: AppTheme.stickerShadowSm,
                  width: double.infinity,
                  child: Text(
                    message.content.isEmpty
                        ? (isUser ? '' : '...')
                        : message.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : AppTheme.textColor,
                      fontSize: 15,
                    ),
                  ),
                ),
                // 图片
                if (message.imageStatus != ImageStatus.none) ...[
                  const SizedBox(height: 8),
                  _buildImage(context),
                ],
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.surface2,
              child: Text('🧑'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppTheme.surface2,
      child: Text(character.avatar, style: const TextStyle(fontSize: 20)),
    );
  }

  Widget _buildImage(BuildContext context) {
    final settings = context.read<SettingsProvider>();
    final url = message.imageUrl;
    final fullUrl = url != null && url.isNotEmpty
        ? (url.startsWith('http') ? url : '${settings.serverUrl}$url')
        : null;

    if (message.imageStatus == ImageStatus.done && fullUrl != null) {
      return GestureDetector(
        onTap: () => _showImageDialog(context, fullUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          child: CachedNetworkImage(
            imageUrl: fullUrl,
            width: 180,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 180,
              height: 240,
              color: AppTheme.surface2,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
      );
    }

    // 生成中
    return Container(
      width: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface2,
        border: Border.all(color: AppTheme.textColor, width: 2),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message.imageStatus == ImageStatus.queued
                ? '排队中...'
                : message.imageStatus == ImageStatus.error
                    ? '生成失败'
                    : '生成图片中...',
            style: const TextStyle(fontSize: 12, color: AppTheme.text2),
          ),
          if (message.imageError != null)
            Text(
              message.imageError!,
              style: const TextStyle(fontSize: 11, color: AppTheme.accent),
            ),
        ],
      ),
    );
  }

  void _showImageDialog(BuildContext context, String fullUrl) {
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
                  imageUrl: fullUrl,
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
                onSaveImage(message.imageUrl!);
              },
            ),
          ],
        ),
      ),
    );
  }
}
