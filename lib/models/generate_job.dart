import '../services/sse_client.dart';

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
    final images = extractImageUrls(job['images']);
    return GenerateJob(
      id: job['id']?.toString() ?? '',
      status: _parseStatus(statusStr),
      error: job['error']?.toString(),
      images: images,
      totalCount: (job['totalCount'] as num?)?.toInt() ??
          (job['count'] as num?)?.toInt() ??
          images.length,
      doneCount: (job['doneCount'] as num?)?.toInt() ?? images.length,
      currentPrompt: job['currentPrompt']?.toString() ??
          job['prompt']?.toString(),
      elapsedMs: (job['elapsedMs'] as num?)?.toInt(),
    );
  }

  static JobStatus _parseStatus(String s) {
    switch (s) {
      case 'queued':
        return JobStatus.queued;
      case 'running':
      case 'generating':
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
