import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../models/preset.dart';
import '../models/generate_job.dart';

/// 图片生成 Provider
class GenerateProvider extends ChangeNotifier {
  final ApiService _api;

  List<GeneratePreset> _presets = [];
  String? _activePresetId;
  GenerateJob? _currentJob;
  bool _isGenerating = false;
  StreamSubscription? _streamSub;

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
      // 如果没有选中的，选第一个
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

  /// 开始生成
  Future<void> startGenerate({
    required String scene,
    int count = 1,
    String mode = 'ai',
  }) async {
    if (_activePresetId == null) return;
    if (_isGenerating) return;

    _isGenerating = true;
    _currentJob = null;
    notifyListeners();

    final stream = _api.generateStream(
      presetId: _activePresetId!,
      scene: scene,
      count: count,
      mode: mode,
    );

    await for (final event in stream) {
      _handleGenerateEvent(event);
    }

    _isGenerating = false;
    notifyListeners();
  }

  void _handleGenerateEvent(Map<String, dynamic> event) {
    final phase = event['phase']?.toString() ?? '';

    switch (phase) {
      case 'queued':
        _currentJob = GenerateJob(
          id: event['jobId']?.toString() ?? '',
          status: JobStatus.queued,
          totalCount: event['count'] as int? ?? 0,
        );
        break;
      case 'running':
      case 'generating':
        _currentJob = _currentJob?.copyWith(
              status: JobStatus.running,
              doneCount: (event['doneCount'] as num?)?.toInt() ??
                  _currentJob?.doneCount ??
                  0,
              totalCount: (event['totalCount'] as num?)?.toInt() ??
                  _currentJob?.totalCount ??
                  0,
              currentPrompt: event['prompt']?.toString(),
              elapsedMs: (event['elapsedMs'] as num?)?.toInt(),
            ) ??
            _currentJob;
        // 如果有新图片
        final images = List<String>.from(event['images'] ?? []);
        if (images.isNotEmpty) {
          _currentJob = _currentJob?.copyWith(images: images);
        }
        break;
      case 'done':
      case 'completed':
        final images = List<String>.from(event['images'] ?? []);
        _currentJob = GenerateJob(
          id: event['jobId']?.toString() ?? _currentJob?.id ?? '',
          status: JobStatus.done,
          images: images,
          totalCount: images.length,
          doneCount: images.length,
          elapsedMs: (event['elapsedMs'] as num?)?.toInt(),
        );
        break;
      case 'error':
        _currentJob = _currentJob?.copyWith(
              status: JobStatus.error,
              error: event['error']?.toString() ?? '生成失败',
            ) ??
            _currentJob;
        break;
      default:
        // 尝试从事件中提取图片
        final images = List<String>.from(event['images'] ?? []);
        if (images.isNotEmpty && _currentJob != null) {
          _currentJob = _currentJob!.copyWith(images: images);
        }
    }
    notifyListeners();
  }

  Future<void> cancelCurrent() async {
    if (_currentJob?.id != null) {
      await _api.cancelGenerateJob(_currentJob!.id);
    }
    _isGenerating = false;
    _currentJob = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    super.dispose();
  }
}
