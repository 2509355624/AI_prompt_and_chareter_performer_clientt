import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/preset.dart';
import '../models/generate_job.dart';
import '../models/character.dart';
import '../models/chat_message.dart';

/// API 服务层
/// 封装所有后端接口调用
class ApiService {
  final Dio _dio = Dio();
  String _baseUrl = '';

  String get baseUrl => _baseUrl;

  void setBaseUrl(String url) {
    // 规范化 URL
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _dio.options.baseUrl = _baseUrl;
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

  /// 获取生成预设列表
  Future<Map<String, dynamic>> getGeneratePresets() async {
    final response = await _dio.get('/api/comfy/generate-presets');
    return Map<String, dynamic>.from(response.data);
  }

  /// 获取生成设置
  Future<Map<String, dynamic>> getGenerateSettings() async {
    final response = await _dio.get('/api/comfy/generate-settings');
    return Map<String, dynamic>.from(response.data);
  }

  /// 获取 Checkpoint 列表
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
          options: Options(
            headers: {
              'Accept': 'text/event-stream',
            },
            responseType: ResponseType.stream,
          ),
        );

        final stream = response.data.stream;
        String buffer = '';

        await for (final chunk in stream) {
          final text = utf8.decode(chunk);
          buffer += text;

          // 按行分割处理 SSE 事件
          final lines = buffer.split('\n');
          buffer = lines.removeLast(); // 保留不完整的行

          for (final line in lines) {
            if (line.startsWith('data: ')) {
              final dataStr = line.substring(6).trim();
              if (dataStr.isEmpty) continue;
              try {
                final json = jsonDecode(dataStr);
                controller.add(Map<String, dynamic>.from(json));
              } catch (_) {
                controller.add({'raw': dataStr});
              }
            }
          }
        }

        controller.close();
      } catch (e) {
        controller.addError(e);
        controller.close();
      }
    }();

    return controller.stream;
  }

  /// 取消生成任务
  Future<bool> cancelGenerateJob(String jobId) async {
    try {
      await _dio.post('/api/comfy/generate-jobs/$jobId/cancel');
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 获取最近的生成任务
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

  /// 获取角色列表
  Future<List<Character>> getCharacters() async {
    final response = await _dio.get('/api/characters');
    final list = List.from(response.data);
    return list.map((e) => Character.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// 获取对话历史
  Future<Map<String, dynamic>> getChatHistory(String characterId) async {
    final response = await _dio.get('/api/chat-history/$characterId');
    return Map<String, dynamic>.from(response.data);
  }

  /// 发起一轮对话（SSE 流式）。密钥由服务端 .env 解析，客户端不传。
  Stream<Map<String, dynamic>> chatTurnStream({
    required String characterId,
    required List<Map<String, dynamic>> messages,
    required String systemPrompt,
    String conversationSummary = '',
    String appearancePrompt = '',
    String outfitPrompt = '',
    List<Map<String, dynamic>> turnMemory = const [],
  }) {
    final controller = StreamController<Map<String, dynamic>>();

    () async {
      try {
        // 第一步：创建 chat-turn（provider/model/key 走服务端默认）
        final createResp = await _dio.post('/api/chat-turn', data: {
          'characterId': characterId,
          'messages': messages,
          'systemPrompt': systemPrompt,
          'conversationSummary': conversationSummary,
          'appearancePrompt': appearancePrompt,
          'outfitPrompt': outfitPrompt,
          'turnMemory': turnMemory,
        });

        final turnId = createResp.data['turnId']?.toString() ?? '';
        if (turnId.isEmpty) {
          controller.addError('Failed to create chat turn');
          controller.close();
          return;
        }

        // 第二步：订阅 SSE 流
        final response = await _dio.get(
          '/api/chat-turn/$turnId/stream',
          options: Options(
            headers: {
              'Accept': 'text/event-stream',
            },
            responseType: ResponseType.stream,
          ),
        );

        final stream = response.data.stream;
        String buffer = '';

        await for (final chunk in stream) {
          final text = utf8.decode(chunk);
          buffer += text;

          final lines = buffer.split('\n');
          buffer = lines.removeLast();

          for (final line in lines) {
            if (line.startsWith('data: ')) {
              final dataStr = line.substring(6).trim();
              if (dataStr.isEmpty) continue;
              try {
                final json = jsonDecode(dataStr);
                controller.add(Map<String, dynamic>.from(json));
              } catch (_) {
                controller.add({'raw': dataStr});
              }
            }
          }
        }

        controller.close();
      } catch (e) {
        controller.addError(e);
        controller.close();
      }
    }();

    return controller.stream;
  }

  /// 提交角色出图任务
  Future<String?> submitCharacterImage({
    required String characterId,
    required String messageId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final response = await _dio.post('/api/character-image', data: {
        'characterId': characterId,
        'messageId': messageId,
        ...payload,
      });
      return response.data['imageJobId']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// 订阅角色出图进度
  Stream<Map<String, dynamic>> imageJobStream(String jobId) {
    final controller = StreamController<Map<String, dynamic>>();

    () async {
      try {
        final response = await _dio.get(
          '/api/image-jobs/$jobId/stream',
          options: Options(
            headers: {
              'Accept': 'text/event-stream',
            },
            responseType: ResponseType.stream,
          ),
        );

        final stream = response.data.stream;
        String buffer = '';

        await for (final chunk in stream) {
          final text = utf8.decode(chunk);
          buffer += text;

          final lines = buffer.split('\n');
          buffer = lines.removeLast();

          for (final line in lines) {
            if (line.startsWith('data: ')) {
              final dataStr = line.substring(6).trim();
              if (dataStr.isEmpty) continue;
              try {
                final json = jsonDecode(dataStr);
                controller.add(Map<String, dynamic>.from(json));
              } catch (_) {
                controller.add({'raw': dataStr});
              }
            }
          }
        }

        controller.close();
      } catch (e) {
        controller.addError(e);
        controller.close();
      }
    }();

    return controller.stream;
  }

  /// 保存对话历史
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

  /// 获取工作流配置选项
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
