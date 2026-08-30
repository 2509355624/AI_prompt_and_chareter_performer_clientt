import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/sse_client.dart';
import '../models/preset.dart';
import '../models/generate_job.dart';

/// 图片生成 Provider：SSE 进度 + jobId 落盘，切后台可轮询恢复
class GenerateProvider extends ChangeNotifier {
  static const _prefsActiveJobKey = 'activeGenerateJobId';

  final ApiService _api;

  List<GeneratePreset> _presets = [];
  String? _activePresetId;
  GenerateJob? _currentJob;
  bool _isGenerating = false;
  String? _lastError;
  Timer? _pollTimer;
  bool _resuming = false;

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

  Future<void> _persistActiveJobId(String? jobId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (jobId == null || jobId.isEmpty) {
        await prefs.remove(_prefsActiveJobKey);
      } else {
        await prefs.setString(_prefsActiveJobKey, jobId);
      }
    } catch (e) {
      debugPrint('persist jobId failed: $e');
    }
  }

  Future<String?> _readPersistedJobId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefsActiveJobKey);
    } catch (_) {
      return null;
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  bool _isTerminal(JobStatus? status) {
    return status == JobStatus.done ||
        status == JobStatus.error ||
        status == JobStatus.cancelled;
  }

  Future<void> _applyJobSnapshot(GenerateJob job) async {
    debugPrint(
      '[Generate] snapshot id=${job.id} status=${job.status} '
      'images=${job.images.length} urls=${job.images}',
    );
    _currentJob = job;
    if (_isTerminal(job.status)) {
      _isGenerating = false;
      _stopPolling();
      await _persistActiveJobId(null);
      if (job.status == JobStatus.error) {
        _lastError = job.error;
      }
    } else {
      _isGenerating = true;
      if (job.id.isNotEmpty) {
        await _persistActiveJobId(job.id);
      }
    }
    notifyListeners();
  }

  void _startPolling(String jobId) {
    if (jobId.isEmpty) return;
    _stopPolling();
    _isGenerating = true;
    unawaited(_persistActiveJobId(jobId));
    notifyListeners();

    Future<void> tick() async {
      final polled = await _api.getGenerateJob(jobId);
      if (polled == null) return;
      await _applyJobSnapshot(polled);
      if (_isTerminal(polled.status)) {
        _stopPolling();
      }
    }

    unawaited(tick());
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(tick());
    });
  }

  /// 进页 / 回前台：用服务端 active 或本地 jobId 恢复任务
  Future<void> resumeIfNeeded() async {
    if (_isGenerating || _resuming) return;
    _resuming = true;
    try {
      GenerateJob? job = await _api.getActiveGenerateJob();
      if (job == null) {
        final id = await _readPersistedJobId();
        if (id != null && id.isNotEmpty) {
          job = await _api.getGenerateJob(id);
        }
      }
      if (job == null) return;

      await _applyJobSnapshot(job);
      if (!_isTerminal(job.status) && job.id.isNotEmpty) {
        _startPolling(job.id);
      }
    } catch (e) {
      debugPrint('resumeIfNeeded failed: $e');
    } finally {
      _resuming = false;
    }
  }

  Future<void> startGenerate({
    required String scene,
    int count = 1,
    String mode = 'ai',
  }) async {
    if (_activePresetId == null) return;
    if (_isGenerating) return;

    _stopPolling();
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

      final jobId = _currentJob?.id;
      if (jobId != null && jobId.isNotEmpty) {
        final polled = await _api.getGenerateJob(jobId);
        if (polled != null) {
          await _applyJobSnapshot(polled);
          if (!_isTerminal(polled.status)) {
            _startPolling(jobId);
            return;
          }
          return;
        }
      }
    } catch (e) {
      debugPrint('Generate error: $e');
      final jobId = _currentJob?.id;
      if (jobId != null && jobId.isNotEmpty) {
        await _persistActiveJobId(jobId);
        _startPolling(jobId);
        return;
      }
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
      await _persistActiveJobId(null);
    } finally {
      if (_pollTimer == null && _isTerminal(_currentJob?.status)) {
        _isGenerating = false;
        await _persistActiveJobId(null);
      }
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
      case 'submitting':
      case 'downloading':
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
        debugPrint(
          '[Generate] done jobId=${jobId ?? _currentJob?.id} '
          'imageCount=${doneImages.length} urls=$doneImages',
        );
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

    final id = _currentJob?.id;
    if (id != null && id.isNotEmpty) {
      unawaited(_persistActiveJobId(
        _isTerminal(_currentJob?.status) ? null : id,
      ));
    }
    notifyListeners();
  }

  Future<void> cancelCurrent() async {
    final id = _currentJob?.id;
    _stopPolling();
    if (id != null && id.isNotEmpty) {
      await _api.cancelGenerateJob(id);
    }
    _isGenerating = false;
    _currentJob = _currentJob?.copyWith(status: JobStatus.cancelled);
    await _persistActiveJobId(null);
    notifyListeners();
  }

  Future<void> cancelGenerate() => cancelCurrent();

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
