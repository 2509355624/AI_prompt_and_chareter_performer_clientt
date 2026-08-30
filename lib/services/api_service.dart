import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/generate_job.dart';
import '../models/character.dart';
import '../models/chat_message.dart';
import 'sse_client.dart';

/// API 服务层：客户端只连局域网 baseUrl，密钥全在服务端 .env。
class ApiService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      // 普通 REST；SSE 在 Options 里单独放宽
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  String _baseUrl = '';

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _dio.options.baseUrl = _baseUrl;
  }

  static Options get _sseOptions => Options(
        headers: {'Accept': 'text/event-stream'},
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(hours: 2),
        sendTimeout: const Duration(seconds: 30),
      );

  Stream<Map<String, dynamic>> _readSse(Response response) {
    final controller = StreamController<Map<String, dynamic>>();
    final parser = SseParser();

    () async {
      try {
        final stream = response.data.stream as Stream<dynamic>;
        await for (final chunk in stream) {
          final bytes = chunk is List<int>
              ? chunk
              : (chunk as List).cast<int>();
          for (final event in parser.push(bytes)) {
            controller.add(event);
          }
        }
        final last = parser.finish();
        if (last != null) controller.add(last);
        await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  // ============================================================
  //  健康检查
  // ============================================================

  Future<bool> checkConnection() async {
    try {
      final response = await _dio.get('/api/comfy/health');
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getComfyHealth() async {
    try {
      final response = await _dio.get('/api/comfy/health');
      return Map<String, dynamic>.from(response.data);
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  // ============================================================
  //  图片生成相关
  // ============================================================

  Future<Map<String, dynamic>> getGeneratePresets() async {
    final response = await _dio.get('/api/comfy/generate-presets');
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getGenerateSettings() async {
    final response = await _dio.get('/api/comfy/generate-settings');
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<String>> getCheckpoints() async {
    try {
      final response = await _dio.get('/api/comfy/checkpoints');
      final data = Map<String, dynamic>.from(response.data);
      return List<String>.from(data['checkpoints'] ?? []);
    } catch (_) {
      return [];
    }
  }

  /// 发起生成任务（SSE 流式）
  Stream<Map<String, dynamic>> generateStream({
    required String presetId,
    required String scene,
    int count = 1,
    String mode = 'ai',
    Map<String, dynamic> overrides = const {},
  }) {
    final controller = StreamController<Map<String, dynamic>>();

    () async {
      try {
        final response = await _dio.post(
          '/api/comfy/generate',
          data: {
            'presetId': presetId,
            'scene': scene,
            'count': count,
            'mode': mode,
            'overrides': overrides,
            'stream': true,
          },
          options: _sseOptions,
        );
        await for (final event in _readSse(response)) {
          controller.add(event);
        }
        await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  Future<bool> cancelGenerateJob(String jobId) async {
    try {
      await _dio.post('/api/comfy/generate-jobs/$jobId/cancel');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<GenerateJob?> getGenerateJob(String jobId) async {
    try {
      final response = await _dio.get('/api/comfy/generate-jobs/$jobId');
      final data = Map<String, dynamic>.from(response.data);
      final job = data['job'];
      if (job is Map) {
        return GenerateJob.fromJson({'job': job});
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<GenerateJob?> getActiveGenerateJob() async {
    try {
      final response = await _dio.get('/api/comfy/generate-jobs/active');
      final data = Map<String, dynamic>.from(response.data);
      final job = data['job'];
      if (job is Map) {
        return GenerateJob.fromJson({'job': job});
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<List<GenerateJob>> getRecentJobs({int limit = 10}) async {
    try {
      final response =
          await _dio.get('/api/comfy/generate-jobs', queryParameters: {
        'limit': limit,
      });
      final data = Map<String, dynamic>.from(response.data);
      final jobs = List.from(data['jobs'] ?? []);
      return jobs
          .map((j) => GenerateJob.fromJson({'job': j}))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ============================================================
  //  角色扮演相关
  // ============================================================

  Future<List<Character>> getCharacters() async {
    final response = await _dio.get('/api/characters');
    final list = List.from(response.data);
    return list
        .map((e) => Character.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> getChatHistory(String characterId) async {
    final response = await _dio.get('/api/chat-history/$characterId');
    return Map<String, dynamic>.from(response.data);
  }

  /// 发起一轮对话（SSE）。密钥由服务端 .env 解析。
  Stream<Map<String, dynamic>> chatTurnStream({
    required String characterId,
    required List<Map<String, dynamic>> messages,
    required String systemPrompt,
    String conversationSummary = '',
    String appearancePrompt = '',
    String outfitPrompt = '',
    List<Map<String, dynamic>> turnMemory = const [],
    Map<String, dynamic>? previousVisual,
  }) {
    final controller = StreamController<Map<String, dynamic>>();

    () async {
      try {
        final body = <String, dynamic>{
          'characterId': characterId,
          'messages': messages,
          'systemPrompt': systemPrompt,
          'conversationSummary': conversationSummary,
          'appearancePrompt': appearancePrompt,
          'outfitPrompt': outfitPrompt,
          'turnMemory': turnMemory,
        };
        if (previousVisual != null) {
          body['previousVisual'] = previousVisual;
        }

        final createResp = await _dio.post('/api/chat-turn', data: body);
        final turnId = createResp.data['turnId']?.toString() ?? '';
        if (turnId.isEmpty) {
          controller.addError('Failed to create chat turn');
          await controller.close();
          return;
        }
        controller.add({'event': 'turn_created', 'turnId': turnId});

        final response = await _dio.get(
          '/api/chat-turn/$turnId/stream',
          options: _sseOptions,
        );
        await for (final event in _readSse(response)) {
          controller.add(event);
        }
        await controller.close();
      } catch (e) {
        // 服务端主动 end() 后，部分平台会抛 Connection closed；不当硬错误往上抛
        final msg = e.toString();
        if (msg.contains('Connection closed') ||
            msg.contains('Connection reset')) {
          debugPrint('chat-turn SSE hangup (treated as end): $e');
          if (!controller.isClosed) await controller.close();
          return;
        }
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  Future<Map<String, dynamic>?> getChatTurn(String turnId) async {
    try {
      final response = await _dio.get('/api/chat-turn/$turnId');
      final data = Map<String, dynamic>.from(response.data as Map);
      final turn = data['turn'];
      if (turn is Map) return Map<String, dynamic>.from(turn);
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 入队角色出图（与 Web 一致走 `/api/image-jobs`；密钥服务端补齐）
  Future<String?> createImageJob({
    required String characterId,
    required String messageId,
    required String replySnippet,
    String userMessage = '',
    Map<String, dynamic>? visual,
    Map<String, dynamic>? previousVisual,
    String emotion = '平静',
    num? intensity,
  }) async {
    try {
      final response = await _dio.post('/api/image-jobs', data: {
        'characterId': characterId,
        'messageId': messageId,
        'replySnippet': replySnippet,
        'userMessage': userMessage,
        'emotion': emotion,
        if (intensity != null) 'intensity': intensity,
        if (visual != null) 'visual': visual,
        if (previousVisual != null) 'previousVisual': previousVisual,
      });
      return response.data['imageJobId']?.toString();
    } catch (e) {
      throw Exception('出图入队失败：$e');
    }
  }

  Stream<Map<String, dynamic>> imageJobStream(String jobId) {
    final controller = StreamController<Map<String, dynamic>>();

    () async {
      try {
        final response = await _dio.get(
          '/api/image-jobs/$jobId/stream',
          options: _sseOptions,
        );
        await for (final event in _readSse(response)) {
          controller.add(event);
        }
        await controller.close();
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError(e);
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  Future<bool> saveChatHistory({
    required String characterId,
    required List<ChatMessage> messages,
    String summary = '',
    List<Map<String, dynamic>> turnMemory = const [],
  }) async {
    try {
      await _dio.post('/api/chat-history/$characterId', data: {
        'messages': messages
            .map((m) => {
                  'id': m.id,
                  'role': m.role == MessageRole.user ? 'user' : 'assistant',
                  'content': m.content,
                  'imageUrl': m.imageUrl,
                  'imageStatus': m.imageStatus.name,
                  'imageError': m.imageError,
                  'imageJobId': m.imageJobId,
                })
            .toList(),
        'summary': summary,
        'turnMemory': turnMemory,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> getWorkflowOptions() async {
    try {
      final response = await _dio.get('/api/comfy/workflow-options');
      return Map<String, dynamic>.from(response.data);
    } catch (_) {
      return {};
    }
  }

  void dispose() {
    _dio.close();
  }
}
