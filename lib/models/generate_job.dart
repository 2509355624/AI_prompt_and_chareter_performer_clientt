/// 生成任务状态
enum JobStatus { queued, running, done, error, cancelled }

/// 生成任务
class GenerateJob {
  final String id;
  final JobStatus status;
  final String? error;
  final List<String> images; // 图片 URL 列表
  final int totalCount;
  final int doneCount;
  final String? currentPrompt;
  final int? elapsedMs;

  GenerateJob({
    required this.id,
    required this.status,
    this.error,
    this.images = const [],
    this.totalCount = 0,
    this.doneCount = 0,
    this.currentPrompt,
    this.elapsedMs,
  });

  factory GenerateJob.fromJson(Map<String, dynamic> json) {
    final job = json['job'] ?? json;
    final statusStr = job['status']?.toString() ?? 'queued';
    return GenerateJob(
      id: job['id']?.toString() ?? '',
      status: _parseStatus(statusStr),
      error: job['error']?.toString(),
      images: (job['images'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      totalCount: (job['totalCount'] as num?)?.toInt() ??
          (job['count'] as num?)?.toInt() ??
          0,
      doneCount: (job['doneCount'] as num?)?.toInt() ??
          (job['images'] as List?)?.length ??
          0,
      currentPrompt: job['currentPrompt']?.toString(),
      elapsedMs: (job['elapsedMs'] as num?)?.toInt(),
    );
  }

  static JobStatus _parseStatus(String s) {
    switch (s) {
      case 'queued':
        return JobStatus.queued;
      case 'running':
        return JobStatus.running;
      case 'done':
      case 'completed':
        return JobStatus.done;
      case 'error':
      case 'failed':
        return JobStatus.error;
      case 'cancelled':
      case 'canceled':
        return JobStatus.cancelled;
      default:
        return JobStatus.queued;
    }
  }

  GenerateJob copyWith({
    String? id,
    JobStatus? status,
    String? error,
    List<String>? images,
    int? totalCount,
    int? doneCount,
    String? currentPrompt,
    int? elapsedMs,
  }) {
    return GenerateJob(
      id: id ?? this.id,
      status: status ?? this.status,
      error: error ?? this.error,
      images: images ?? this.images,
      totalCount: totalCount ?? this.totalCount,
      doneCount: doneCount ?? this.doneCount,
      currentPrompt: currentPrompt ?? this.currentPrompt,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }
}

/// SSE 事件
class SseEvent {
  final String phase;
  final Map<String, dynamic> data;

  SseEvent({required this.phase, required this.data});

  factory SseEvent.fromDataString(String dataStr) {
    try {
      // 尝试解析 JSON
      if (dataStr.startsWith('{') || dataStr.startsWith('[')) {
        // 简单 JSON 解析
        final json = _parseSimpleJson(dataStr);
        final phase = json['phase']?.toString() ?? 'data';
        return SseEvent(phase: phase, data: json);
      }
    } catch (_) {}
    return SseEvent(phase: 'data', data: {'raw': dataStr});
  }

  // 简易 JSON 解析（避免引入额外依赖）
  static Map<String, dynamic> _parseSimpleJson(String s) {
    // 用 Uri 解码？不行，用正则太脆弱
    // 这里我们在 service 层用 dart:convert 解析
    return {};
  }
}
