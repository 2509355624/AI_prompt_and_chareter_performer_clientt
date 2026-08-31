import '../services/sse_client.dart';

/// 生成任务状态
enum JobStatus { queued, running, done, error, cancelled }

/// 单张生成结果（URL + 本张提示词）
class GenerateResultImage {
  final String url;
  final String prompt;

  const GenerateResultImage({required this.url, this.prompt = ''});

  factory GenerateResultImage.fromRef(GenerateImageRef ref) {
    return GenerateResultImage(url: ref.url, prompt: ref.prompt);
  }
}

/// 生成任务
class GenerateJob {
  final String id;
  final JobStatus status;
  final String? error;
  final List<GenerateResultImage> results;
  final int totalCount;
  final int doneCount;
  final String? currentPrompt;
  final int? elapsedMs;

  GenerateJob({
    required this.id,
    required this.status,
    this.error,
    this.results = const [],
    this.totalCount = 0,
    this.doneCount = 0,
    this.currentPrompt,
    this.elapsedMs,
  });

  /// 兼容旧调用：只要 URL 列表
  List<String> get images => results.map((e) => e.url).toList();

  factory GenerateJob.fromJson(Map<String, dynamic> json) {
    final job = json['job'] ?? json;
    final statusStr = job['status']?.toString() ?? 'queued';
    final refs = extractGenerateImages(job['images']);
    final results =
        refs.map(GenerateResultImage.fromRef).toList(growable: false);
    return GenerateJob(
      id: job['id']?.toString() ?? '',
      status: _parseStatus(statusStr),
      error: job['error']?.toString(),
      results: results,
      totalCount: (job['totalCount'] as num?)?.toInt() ??
          (job['count'] as num?)?.toInt() ??
          results.length,
      doneCount: (job['doneCount'] as num?)?.toInt() ?? results.length,
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
    List<GenerateResultImage>? results,
    List<String>? images,
    int? totalCount,
    int? doneCount,
    String? currentPrompt,
    int? elapsedMs,
  }) {
    List<GenerateResultImage>? nextResults = results;
    if (nextResults == null && images != null) {
      nextResults = images
          .map((u) => GenerateResultImage(url: u))
          .toList(growable: false);
    }
    return GenerateJob(
      id: id ?? this.id,
      status: status ?? this.status,
      error: error ?? this.error,
      results: nextResults ?? this.results,
      totalCount: totalCount ?? this.totalCount,
      doneCount: doneCount ?? this.doneCount,
      currentPrompt: currentPrompt ?? this.currentPrompt,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }
}
