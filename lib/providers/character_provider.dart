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
  StreamSubscription? _imageSub;
  Map<String, dynamic>? _lastVisual;

  List<Character> get characters => _characters;
  Character? get currentCharacter => _currentCharacter;
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;

  CharacterProvider(this._api);

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
    _lastVisual = null;
    notifyListeners();
    loadChatHistory();
  }

  Future<void> loadChatHistory() async {
    if (_currentCharacter == null) return;
    try {
      final data = await _api.getChatHistory(_currentCharacter!.id);
      final msgList = List.from(data['messages'] ?? []);
      _messages = msgList
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      // 从历史里尽量恢复上一张 visual 连续性（若有存）
      for (var i = _messages.length - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m.role == MessageRole.assistant &&
            m.imageUrl != null &&
            m.imageUrl!.isNotEmpty) {
          break;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Load chat history error: $e');
    }
  }

  Future<void> sendMessage(String text) async {
    if (_currentCharacter == null || _isSending || text.trim().isEmpty) return;

    _isSending = true;
    final userText = text.trim();

    final userMsg = ChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      role: MessageRole.user,
      content: userText,
    );
    _messages.add(userMsg);

    final aiMsgId = 'ai_${DateTime.now().millisecondsSinceEpoch}';
    final aiMsg = ChatMessage(
      id: aiMsgId,
      role: MessageRole.assistant,
      content: '',
      imageStatus: ImageStatus.queued,
    );
    _messages.add(aiMsg);
    notifyListeners();

    final previousVisual = _lastVisual;
    var fullReply = '';

    try {
      final msgsForApi = _messages
          .where((m) =>
              m.role == MessageRole.user ||
              (m.role == MessageRole.assistant && m.content.isNotEmpty))
          .map((m) => {
                'role': m.role == MessageRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final stream = _api.chatTurnStream(
        characterId: _currentCharacter!.id,
        messages: msgsForApi,
        systemPrompt: _currentCharacter!.systemPrompt,
        appearancePrompt: _currentCharacter!.appearancePrompt,
        outfitPrompt: _currentCharacter!.outfitPrompt,
        previousVisual: previousVisual,
      );

      Map<String, dynamic>? turnDonePayload;
      String? turnError;

      await for (final event in stream) {
        final type = event['event']?.toString() ?? '';

        if (type == 'reply_delta') {
          final accumulated = event['accumulated']?.toString();
          if (accumulated != null && accumulated.isNotEmpty) {
            fullReply = accumulated;
          } else {
            final delta = event['delta']?.toString() ?? '';
            if (delta.isNotEmpty) fullReply += delta;
          }
          _patchAiMessage(aiMsgId, content: fullReply);
        } else if (type == 'turn_done') {
          turnDonePayload = event;
          final reply = event['reply']?.toString();
          if (reply != null && reply.isNotEmpty) {
            fullReply = reply;
            _patchAiMessage(aiMsgId, content: fullReply);
          }
        } else if (type == 'turn_error') {
          turnError = event['error']?.toString() ?? '对话生成失败';
        } else if (type == 'snapshot') {
          final status = event['status']?.toString() ?? '';
          if (status == 'completed' && event['result'] is Map) {
            turnDonePayload = Map<String, dynamic>.from(event['result'] as Map);
            final reply = turnDonePayload!['reply']?.toString();
            if (reply != null && reply.isNotEmpty) {
              fullReply = reply;
              _patchAiMessage(aiMsgId, content: fullReply);
            }
          } else if (status == 'failed') {
            turnError = event['error']?.toString() ?? '对话生成失败';
          } else {
            final snapReply = event['replyText']?.toString() ?? '';
            if (snapReply.isNotEmpty) {
              fullReply = snapReply;
              _patchAiMessage(aiMsgId, content: fullReply);
            }
          }
        } else if (event['reply'] != null &&
            type.isEmpty &&
            fullReply.isEmpty) {
          // 兼容无 event 名的旧格式
          fullReply = event['reply'].toString();
          turnDonePayload = event;
          _patchAiMessage(aiMsgId, content: fullReply);
        }
      }

      if (turnError != null) {
        _patchAiMessage(
          aiMsgId,
          content: '出错了：$turnError',
          imageStatus: ImageStatus.error,
          imageError: turnError,
        );
        return;
      }

      if (fullReply.isEmpty && turnDonePayload != null) {
        fullReply = turnDonePayload!['reply']?.toString() ?? '';
      }

      _patchAiMessage(aiMsgId, content: fullReply);

      // 与 Web 一致：对话结束后单独入队出图
      final visual = _asMap(turnDonePayload?['visual']);
      if (visual != null) {
        _lastVisual = visual;
      }

      final emotionRoot = turnDonePayload?['emotionAnalysis'];
      Map<String, dynamic>? emotionBlock;
      if (emotionRoot is Map) {
        final nested = emotionRoot['emotionAnalysis'];
        emotionBlock = nested is Map
            ? Map<String, dynamic>.from(nested)
            : Map<String, dynamic>.from(emotionRoot);
      }

      final emotion =
          emotionBlock?['primaryEmotion']?.toString() ?? '平静';
      final intensity = emotionBlock?['intensity'] as num?;

      try {
        final imageJobId = await _api.createImageJob(
          characterId: _currentCharacter!.id,
          messageId: aiMsgId,
          replySnippet: fullReply,
          userMessage: userText,
          visual: visual,
          previousVisual: previousVisual,
          emotion: emotion,
          intensity: intensity,
        );

        if (imageJobId != null && imageJobId.isNotEmpty) {
          _patchAiMessage(
            aiMsgId,
            imageJobId: imageJobId,
            imageStatus: ImageStatus.queued,
          );
          _subscribeImageJob(imageJobId, aiMsgId);
        } else {
          _patchAiMessage(aiMsgId, imageStatus: ImageStatus.none);
        }
      } catch (e) {
        debugPrint('Image job enqueue error: $e');
        _patchAiMessage(
          aiMsgId,
          imageStatus: ImageStatus.error,
          imageError: e.toString(),
        );
      }

      await _saveHistory();
    } catch (e) {
      _patchAiMessage(
        aiMsgId,
        content: fullReply.isNotEmpty ? fullReply : '出错了：$e',
        imageStatus: ImageStatus.error,
        imageError: e.toString(),
      );
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  void _patchAiMessage(
    String id, {
    String? content,
    ImageStatus? imageStatus,
    String? imageUrl,
    String? imageError,
    String? imageJobId,
  }) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0) return;
    _messages[idx] = _messages[idx].copyWith(
      content: content,
      imageStatus: imageStatus,
      imageUrl: imageUrl,
      imageError: imageError,
      imageJobId: imageJobId,
    );
    notifyListeners();
  }

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  void _subscribeImageJob(String jobId, String messageId) {
    _imageSub?.cancel();
    _imageSub = _api.imageJobStream(jobId).listen(
      (event) {
        final type = event['event']?.toString() ?? '';

        if (type == 'image_running' || type == 'vram_ready') {
          _patchAiMessage(messageId, imageStatus: ImageStatus.running);
          return;
        }
        if (type == 'vram_waiting') {
          _patchAiMessage(messageId, imageStatus: ImageStatus.running);
          return;
        }
        if (type == 'image_done') {
          _applyImageResult(messageId, event);
          return;
        }
        if (type == 'image_failed') {
          _patchAiMessage(
            messageId,
            imageStatus: ImageStatus.error,
            imageError: event['error']?.toString() ?? '出图失败',
          );
          _saveHistory();
          return;
        }
        if (type == 'snapshot') {
          final status = event['status']?.toString() ?? '';
          if (status == 'completed' && event['result'] is Map) {
            _applyImageResult(
              messageId,
              Map<String, dynamic>.from(event['result'] as Map),
            );
          } else if (status == 'failed') {
            _patchAiMessage(
              messageId,
              imageStatus: ImageStatus.error,
              imageError: event['error']?.toString() ?? '出图失败',
            );
            _saveHistory();
          } else if (status == 'running' || status == 'queued') {
            _patchAiMessage(
              messageId,
              imageStatus: status == 'queued'
                  ? ImageStatus.queued
                  : ImageStatus.running,
            );
          }
        }
      },
      onError: (e) {
        _patchAiMessage(
          messageId,
          imageStatus: ImageStatus.error,
          imageError: e.toString(),
        );
      },
    );
  }

  void _applyImageResult(String messageId, Map<String, dynamic> data) {
    final imageUrl = data['imageUrl']?.toString() ??
        data['url']?.toString() ??
        '';
    final ok = data['ok'] != false;
    if (ok && imageUrl.isNotEmpty) {
      final visual = _asMap(data['visual']);
      if (visual != null) _lastVisual = visual;
      _patchAiMessage(
        messageId,
        imageStatus: ImageStatus.done,
        imageUrl: imageUrl,
        imageError: '',
      );
      _saveHistory();
    } else if (data['error'] != null) {
      _patchAiMessage(
        messageId,
        imageStatus: ImageStatus.error,
        imageError: data['error'].toString(),
      );
      _saveHistory();
    }
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
    _lastVisual = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _imageSub?.cancel();
    super.dispose();
  }
}
