import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/sse_client.dart';
import '../models/preset.dart';
import '../models/generate_job.dart';

/// 图片生成 Provider
class GenerateProvider extends ChangeNotifier {
  final ApiService _api;

  List<GeneratePreset> _presets = [];
  String? _activePresetId;
  GenerateJob? _currentJob;
  bool _isGenerating = false;
  String? _lastError;

  List<GeneratePreset> get presets => _presets;
  String? get activePresetId => _activePresetId;
  GeneratePreset? get activePreset {
    if (_activePresetId == null) return null;
    try {
      return _presets.firstWhere((p) => p.id == _activePresetId);
    } catch (_) {
      return null;
    }
  }

  GenerateJob? get currentJob => _currentJob;
  bool get isGenerating => _isGenerating;
  String? get lastError => _lastError;

  GenerateProvider(this._api);

  Future<void> loadPresets() async {
    try {
      final data = await _api.getGeneratePresets();
      final list = List.from(data['presets'] ?? []);
      _presets = list
          .map((e) => GeneratePreset.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _activePresetId = data['activePresetId']?.toString();
      if (_activePresetId?.isEmpty == true) _activePresetId = null;
      if (_activePresetId == null && _presets.isNotEmpty) {
        _activePresetId = _presets.first.id;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Load presets error: $e');
    }
  }

  void selectPreset(String id) {
    _activePresetId = id;
    notifyListeners();
  }

  Future<void> startGenerate({
    required String scene,
    int count = 1,
    String mode = 'ai',
  }) async {
    if (_activePresetId == null) return;
    if (_isGenerating) return;

    _isGenerating = true;
    _lastError = null;
    _currentJob = GenerateJob(
      id: '',
      status: JobStatus.queued,
      totalCount: count,
    );
    notifyListeners();

    try {
      final stream = _api.generateStream(
        presetId: _activePresetId!,
        scene: scene,
        count: count,
        mode: mode,
      );

      await for (final event in stream) {
        _handleGenerateEvent(event);
      }

      // SSE 结束后若仍无图，轮询一次任务详情（与 Web 兜底一致）
      final jobId = _currentJob?.id;
      if (jobId != null &&
          jobId.isNotEmpty &&
          (_currentJob?.images.isEmpty ?? true) &&
          _currentJob?.status != JobStatus.error) {
        final polled = await _api.getGenerateJob(jobId);
        if (polled != null && polled.images.isNotEmpty) {
          _currentJob = polled;
        }
      }
    } catch (e) {
      debugPrint('Generate error: $e');
      _lastError = e.toString();
      _currentJob = _currentJob?.copyWith(
            status: JobStatus.error,
            error: e.toString(),
          ) ??
          GenerateJob(
            id: '',
            status: JobStatus.error,
            error: e.toString(),
          );
    } finally {
      _isGenerating = false;
      notifyListeners();
    }
  }

  void _handleGenerateEvent(Map<String, dynamic> event) {
    final phase = event['phase']?.toString() ?? '';
    final jobId = event['jobId']?.toString();
    final images = extractImageUrls(event['images']);

    switch (phase) {
      case 'queued':
      case 'job':
        _currentJob = GenerateJob(
          id: jobId ?? _currentJob?.id ?? '',
          status: JobStatus.queued,
          totalCount: (event['count'] as num?)?.toInt() ??
              _currentJob?.totalCount ??
              0,
          images: images.isNotEmpty ? images : (_currentJob?.images ?? const []),
        );
        break;
      case 'running':
      case 'generating':
      case 'expanding':
      case 'expanded':
      case 'manual':
      case 'starting':
        _currentJob = (_currentJob ??
                GenerateJob(
                  id: jobId ?? '',
                  status: JobStatus.running,
                ))
            .copyWith(
          id: (jobId != null && jobId.isNotEmpty) ? jobId : null,
          status: JobStatus.running,
          doneCount: (event['doneCount'] as num?)?.toInt(),
          totalCount: (event['totalCount'] as num?)?.toInt() ??
              (event['count'] as num?)?.toInt(),
          currentPrompt: event['prompt']?.toString() ??
              event['message']?.toString(),
          elapsedMs: (event['elapsedMs'] as num?)?.toInt(),
          images: images.isNotEmpty ? images : null,
        );
        break;
      case 'done':
      case 'completed':
        final doneImages =
            images.isNotEmpty ? images : (_currentJob?.images ?? const []);
        _currentJob = GenerateJob(
          id: jobId ?? _currentJob?.id ?? '',
          status: JobStatus.done,
          images: doneImages,
          totalCount: doneImages.isNotEmpty
              ? doneImages.length
              : (_currentJob?.totalCount ?? 0),
          doneCount: doneImages.length,
          elapsedMs: (event['elapsedMs'] as num?)?.toInt(),
        );
        break;
      case 'error':
      case 'cancelled':
        _currentJob = (_currentJob ??
                GenerateJob(id: jobId ?? '', status: JobStatus.error))
            .copyWith(
          id: (jobId != null && jobId.isNotEmpty) ? jobId : null,
          status: phase == 'cancelled'
              ? JobStatus.cancelled
              : JobStatus.error,
          error: event['error']?.toString() ??
              event['message']?.toString() ??
              '生成失败',
        );
        _lastError = _currentJob?.error;
        break;
      default:
        if (images.isNotEmpty) {
          _currentJob = (_currentJob ??
                  GenerateJob(id: jobId ?? '', status: JobStatus.running))
              .copyWith(
            id: (jobId != null && jobId.isNotEmpty) ? jobId : null,
            images: images,
            doneCount: images.length,
          );
        } else if (jobId != null && jobId.isNotEmpty) {
          _currentJob = (_currentJob ??
                  GenerateJob(id: jobId, status: JobStatus.running))
              .copyWith(id: jobId);
        }
    }
    notifyListeners();
  }

  Future<void> cancelCurrent() async {
    final id = _currentJob?.id;
    if (id != null && id.isNotEmpty) {
      await _api.cancelGenerateJob(id);
    }
    _isGenerating = false;
    _currentJob = _currentJob?.copyWith(status: JobStatus.cancelled);
    notifyListeners();
  }

  /// 页面里也可能叫 cancelCurrent
  Future<void> cancelGenerate() => cancelCurrent();
}
