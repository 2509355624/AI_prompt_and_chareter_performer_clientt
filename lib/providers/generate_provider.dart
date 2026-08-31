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
  GeneratePreset? _draft;
  GenerateExpandSettings _expandSettings = const GenerateExpandSettings();
  List<String> _checkpoints = [];
  List<String> _loras = [];
  List<String> _upscaleModels = [];
  List<String> _samplerOptions = const [
    'euler',
    'euler_ancestral',
    'dpmpp_2m',
    'dpmpp_sde',
    'uni_pc',
  ];
  List<String> _schedulerOptions = const [
    'simple',
    'normal',
    'karras',
    'exponential',
    'sgm_uniform',
  ];
  GenerateJob? _currentJob;
  bool _isGenerating = false;
  String? _lastError;
  Timer? _pollTimer;
  bool _resuming = false;
  bool _savingPreset = false;

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

  /// 当前编辑中的配置（选预设 / 改表单后即时生效，不必先保存）
  GeneratePreset? get draft => _draft ?? activePreset;
  GenerateExpandSettings get expandSettings => _expandSettings;
  List<String> get checkpoints => _checkpoints;
  List<String> get loraNames => _loras;
  List<String> get upscaleModels => _upscaleModels;
  List<String> get samplerOptions => _samplerOptions;
  List<String> get schedulerOptions => _schedulerOptions;
  bool get savingPreset => _savingPreset;

  GenerateJob? get currentJob => _currentJob;
  bool get isGenerating => _isGenerating;
  String? get lastError => _lastError;

  GenerateProvider(this._api);

  void _applyPresetList(Map<String, dynamic> data) {
    final list = List.from(data['presets'] ?? []);
    _presets = list
        .map((e) => GeneratePreset.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    _activePresetId = data['activePresetId']?.toString();
    if (_activePresetId?.isEmpty == true) _activePresetId = null;
    if (_activePresetId == null && _presets.isNotEmpty) {
      _activePresetId = _presets.first.id;
    }
    final active = activePreset;
    if (active != null) {
      _draft = active;
      if (active.samplerOptions.isNotEmpty) {
        _samplerOptions = active.samplerOptions;
      }
      if (active.schedulerOptions.isNotEmpty) {
        _schedulerOptions = active.schedulerOptions;
      }
    }
  }

  Future<void> loadPresets() async {
    try {
      final data = await _api.getGeneratePresets();
      _applyPresetList(data);
      final defaults = data['defaults'];
      if (defaults is Map) {
        final d = Map<String, dynamic>.from(defaults);
        final so = d['samplerOptions'];
        final sch = d['schedulerOptions'];
        if (so is List && so.isNotEmpty) {
          _samplerOptions = so.map((e) => e.toString()).toList();
        }
        if (sch is List && sch.isNotEmpty) {
          _schedulerOptions = sch.map((e) => e.toString()).toList();
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Load presets error: $e');
    }
  }

  Future<void> loadConfigOptions() async {
    try {
      final opts = await _api.getWorkflowOptions();
      final ups = await _api.getUpscaleModels();
      final settingsData = await _api.getGenerateSettings();

      _checkpoints = List<String>.from(opts['checkpoints'] ?? []);
      _loras = List<String>.from(opts['loras'] ?? []);
      _upscaleModels = ups;

      final defaults = opts['defaults'];
      if (defaults is Map) {
        final d = Map<String, dynamic>.from(defaults);
        final so = d['samplerOptions'];
        final sch = d['schedulerOptions'];
        if (so is List && so.isNotEmpty) {
          _samplerOptions = so.map((e) => e.toString()).toList();
        }
        if (sch is List && sch.isNotEmpty) {
          _schedulerOptions = sch.map((e) => e.toString()).toList();
        }
      }

      final settings = settingsData['settings'];
      if (settings is Map) {
        _expandSettings = GenerateExpandSettings.fromJson(
          Map<String, dynamic>.from(settings),
        );
      } else {
        final defaultsSettings = settingsData['defaults'];
        if (defaultsSettings is Map) {
          _expandSettings = GenerateExpandSettings.fromJson(
            Map<String, dynamic>.from(defaultsSettings),
          );
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Load config options error: $e');
    }
  }

  Future<void> selectPreset(String id) async {
    if (id.isEmpty) return;
    _activePresetId = id;
    try {
      final found = _presets.firstWhere((p) => p.id == id);
      _draft = found;
    } catch (_) {
      _draft = null;
    }
    notifyListeners();
    try {
      final data = await _api.activateGeneratePreset(id);
      if (data['ok'] == true) {
        _applyPresetList(data);
      }
    } catch (e) {
      debugPrint('Activate preset failed: $e');
    }
    notifyListeners();
  }

  void updateDraft(GeneratePreset next) {
    _draft = next;
    notifyListeners();
  }

  void updateExpandSettings(GenerateExpandSettings next) {
    _expandSettings = next;
    notifyListeners();
  }

  Future<bool> saveDraftPreset() async {
    final d = draft;
    if (d == null) return false;
    _savingPreset = true;
    notifyListeners();
    try {
      final body = d.toJson();
      if (d.isKrea2) {
        body['workflowEngine'] = 'krea2';
        body['unetName'] =
            d.unetName.isNotEmpty ? d.unetName : d.checkpointName;
        body['checkpointName'] =
            d.checkpointName.isNotEmpty ? d.checkpointName : d.unetName;
        body['enableHires'] = false;
        final loras = List<LoraConfig>.from(d.loras);
        while (loras.length < 3) {
          loras.add(const LoraConfig(name: '(none)', strengthModel: 0));
        }
        body['loras'] = [
          loras[0].toJson(),
          {'name': '(none)', 'strengthModel': 0, 'strengthClip': 0},
          {'name': '(none)', 'strengthModel': 0, 'strengthClip': 0},
        ];
      }
      final data = await _api.upsertGeneratePreset(body);
      if (data['ok'] != true) {
        _lastError = data['error']?.toString() ?? '保存失败';
        return false;
      }
      _applyPresetList(data);
      final saved = data['preset'];
      if (saved is Map) {
        _draft = GeneratePreset.fromJson(Map<String, dynamic>.from(saved));
        _activePresetId = _draft!.id;
      }
      return true;
    } catch (e) {
      _lastError = e.toString();
      debugPrint('Save preset error: $e');
      return false;
    } finally {
      _savingPreset = false;
      notifyListeners();
    }
  }

  Future<bool> deleteActivePreset() async {
    final id = _activePresetId;
    if (id == null || id.isEmpty) return false;
    try {
      final data = await _api.deleteGeneratePreset(id);
      if (data['ok'] != true) {
        _lastError = data['error']?.toString() ?? '删除失败';
        return false;
      }
      _applyPresetList(data);
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<bool> saveExpandSettings() async {
    try {
      final data = await _api.putGenerateSettings(_expandSettings.toJson());
      if (data['ok'] != true) {
        _lastError = data['error']?.toString() ?? '保存失败';
        return false;
      }
      final settings = data['settings'];
      if (settings is Map) {
        _expandSettings = GenerateExpandSettings.fromJson(
          Map<String, dynamic>.from(settings),
        );
      }
      return true;
    } catch (e) {
      _lastError = e.toString();
      return false;
    } finally {
      notifyListeners();
    }
  }

  void createBlankPreset() {
    final blank = GeneratePreset(
      id: '',
      name: '新预设',
      basePrompt: draft?.basePrompt ?? '',
      negativePrompt: draft?.negativePrompt ?? '',
      width: draft?.width ?? 832,
      height: draft?.height ?? 1216,
      steps: draft?.steps ?? 6,
      cfg: draft?.cfg ?? 1,
      sampler: draft?.sampler ?? 'euler',
      scheduler: draft?.scheduler ?? 'simple',
      checkpointName: draft?.checkpointName ?? '',
      workflowEngine: draft?.workflowEngine ?? 'sdxl',
    );
    _draft = blank;
    _activePresetId = null;
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
      'images=${job.images.length} done=${job.doneCount}/${job.totalCount}',
    );
    _currentJob = job;
    if (!_isTerminal(job.status) && job.id.isNotEmpty) {
      _isGenerating = true;
      await _persistActiveJobId(job.id);
    } else {
      _isGenerating = false;
      await _persistActiveJobId(null);
    }
    notifyListeners();
  }

  void _startPolling(String jobId) {
    _stopPolling();
    _isGenerating = true;
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
    final presetId = _activePresetId ?? draft?.id;
    if (presetId == null || presetId.isEmpty) {
      _lastError = '请先选择或保存预设';
      notifyListeners();
      return;
    }
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

    final overrides = draft?.toOverrides() ?? const <String, dynamic>{};

    try {
      final stream = _api.generateStream(
        presetId: presetId,
        scene: scene,
        count: count,
        mode: mode,
        overrides: overrides,
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
