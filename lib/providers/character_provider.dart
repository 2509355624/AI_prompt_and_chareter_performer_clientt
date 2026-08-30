import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../models/character.dart';
import '../models/chat_message.dart';

/// 角色扮演 Provider
class CharacterProvider extends ChangeNotifier {
  final ApiService _api;

  List<Character> _characters = [];
  Character? _currentCharacter;
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  StreamSubscription? _chatSub;
  StreamSubscription? _imageSub;

  List<Character> get characters => _characters;
  Character? get currentCharacter => _currentCharacter;
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;

  CharacterProvider(this._api);

  // ============================================================
  //  角色管理
  // ============================================================

  Future<void> loadCharacters() async {
    _isLoading = true;
    notifyListeners();
    try {
      _characters = await _api.getCharacters();
    } catch (e) {
      debugPrint('Load characters error: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  void selectCharacter(Character character) {
    _currentCharacter = character;
    _messages = [];
    notifyListeners();
    loadChatHistory();
  }

  // ============================================================
  //  对话历史
  // ============================================================

  Future<void> loadChatHistory() async {
    if (_currentCharacter == null) return;
    try {
      final data = await _api.getChatHistory(_currentCharacter!.id);
      final msgList = List.from(data['messages'] ?? []);
      _messages = msgList
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Load chat history error: $e');
    }
  }

  // ============================================================
  //  发送消息
  // ============================================================

  Future<void> sendMessage(String text) async {
    if (_currentCharacter == null || _isSending || text.trim().isEmpty) return;

    _isSending = true;

    // 添加用户消息
    final userMsg = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: text.trim(),
    );
    _messages.add(userMsg);

    // 添加占位的 AI 消息
    final aiMsgId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    final aiMsg = ChatMessage(
      id: aiMsgId,
      role: MessageRole.assistant,
      content: '',
      imageStatus: ImageStatus.queued,
    );
    _messages.add(aiMsg);
    notifyListeners();

    try {
      // 构建消息列表
      final msgsForApi = _messages
          .where((m) =>
              m.role == MessageRole.user ||
              (m.role == MessageRole.assistant && m.content.isNotEmpty))
          .map((m) => {
                'role': m.role == MessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      // 发起对话流式请求（密钥在服务端）
      final stream = _api.chatTurnStream(
        characterId: _currentCharacter!.id,
        messages: msgsForApi,
        systemPrompt: _currentCharacter!.systemPrompt,
        appearancePrompt: _currentCharacter!.appearancePrompt,
        outfitPrompt: _currentCharacter!.outfitPrompt,
      );

      String fullReply = '';
      String? imageJobId;

      await for (final event in stream) {
        final phase = event['phase']?.toString() ?? '';

        if (phase == 'text' || event['content'] != null) {
          // 文本增量
          final delta = event['content']?.toString() ??
              event['delta']?.toString() ??
              '';
          if (delta.isNotEmpty) {
            fullReply += delta;
            final idx = _messages.indexWhere((m) => m.id == aiMsgId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: fullReply);
              notifyListeners();
            }
          }
        } else if (phase == 'done' || event['reply'] != null) {
          // 完成
          final reply = event['reply']?.toString() ?? fullReply;
          if (reply.isNotEmpty) {
            fullReply = reply;
            final idx = _messages.indexWhere((m) => m.id == aiMsgId);
            if (idx >= 0) {
              _messages[idx] = _messages[idx].copyWith(content: fullReply);
            }
          }
          // 提取 imageJobId
          if (event['imageJobId'] != null) {
            imageJobId = event['imageJobId']?.toString();
          }
        } else if (event['imageJobId'] != null && imageJobId == null) {
          imageJobId = event['imageJobId']?.toString();
        }
      }

      // 更新消息内容
      final idx = _messages.indexWhere((m) => m.id == aiMsgId);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(
          content: fullReply,
          imageJobId: imageJobId,
          imageStatus: imageJobId != null ? ImageStatus.running : ImageStatus.none,
        );
        notifyListeners();
      }

      // 如果有出图任务，订阅进度
      if (imageJobId != null) {
        _subscribeImageJob(imageJobId!, aiMsgId);
      }

      // 保存历史
      _saveHistory();
    } catch (e) {
      final idx = _messages.indexWhere((m) => m.id == aiMsgId);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(
          content: '出错了：$e',
          imageStatus: ImageStatus.error,
        );
      }
      notifyListeners();
    }

    _isSending = false;
    notifyListeners();
  }

  void _subscribeImageJob(String jobId, String messageId) {
    _imageSub?.cancel();
    final stream = _api.imageJobStream(jobId);
    _imageSub = stream.listen(
      (event) {
        final status = event['status']?.toString() ?? '';
        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx < 0) return;

        if (status == 'running' || event['phase'] == 'running') {
          _messages[idx] = _messages[idx].copyWith(
            imageStatus: ImageStatus.running,
          );
        } else if (status == 'done' || event['phase'] == 'done') {
          final imageUrl = event['imageUrl']?.toString() ??
              event['url']?.toString() ??
              (event['images'] is List && event['images'].isNotEmpty
                  ? event['images'][0].toString()
                  : '');
          _messages[idx] = _messages[idx].copyWith(
            imageStatus: ImageStatus.done,
            imageUrl: imageUrl,
          );
        } else if (status == 'error' || event['error'] != null) {
          _messages[idx] = _messages[idx].copyWith(
            imageStatus: ImageStatus.error,
            imageError: event['error']?.toString(),
          );
        }
        notifyListeners();
      },
      onError: (e) {
        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx >= 0) {
          _messages[idx] = _messages[idx].copyWith(
            imageStatus: ImageStatus.error,
            imageError: e.toString(),
          );
          notifyListeners();
        }
      },
    );
  }

  Future<void> _saveHistory() async {
    if (_currentCharacter == null) return;
    await _api.saveChatHistory(
      characterId: _currentCharacter!.id,
      messages: _messages,
    );
  }

  void clearMessages() {
    _messages = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _imageSub?.cancel();
    super.dispose();
  }
}
