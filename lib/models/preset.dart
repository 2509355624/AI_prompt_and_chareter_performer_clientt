class GeneratePreset {
  final String id;
  final String name;
  final String workflowEngine;
  final String basePrompt;
  final String negativePrompt;
  final int width;
  final int height;
  final int steps;
  final double cfg;
  final String sampler;
  final String scheduler;
  final double denoise;
  final int seed;
  final String checkpointName;
  final String unetName;
  final String clipName;
  final String clipType;
  final String vaeName;
  final List<LoraConfig> loras;
  final bool enableHires;
  final int hiresWidth;
  final int hiresHeight;
  final double hiresDenoise;
  final int hiresSteps;
  final bool enableUpscale;
  final String upscaleModel;
  final List<String> samplerOptions;
  final List<String> schedulerOptions;

  const GeneratePreset({
    required this.id,
    required this.name,
    this.workflowEngine = 'sdxl',
    this.basePrompt = '',
    this.negativePrompt = '',
    this.width = 832,
    this.height = 1216,
    this.steps = 6,
    this.cfg = 1.0,
    this.sampler = 'euler',
    this.scheduler = 'simple',
    this.denoise = 1.0,
    this.seed = -1,
    this.checkpointName = '',
    this.unetName = '',
    this.clipName = '',
    this.clipType = '',
    this.vaeName = '',
    this.loras = const [],
    this.enableHires = false,
    this.hiresWidth = 1080,
    this.hiresHeight = 1920,
    this.hiresDenoise = 0.4,
    this.hiresSteps = 20,
    this.enableUpscale = false,
    this.upscaleModel = '',
    this.samplerOptions = const [],
    this.schedulerOptions = const [],
  });

  bool get isKrea2 =>
      workflowEngine.toLowerCase() == 'krea2' ||
      checkpointName.toLowerCase().endsWith('.gguf') ||
      unetName.toLowerCase().endsWith('.gguf') ||
      name.toLowerCase().contains('krea2');

  factory GeneratePreset.fromJson(Map<String, dynamic> json) {
    // API is flat; tolerate legacy nested `content`
    final src = json['content'] is Map
        ? {...json, ...Map<String, dynamic>.from(json['content'] as Map)}
        : json;
    final loraRaw = src['loras'];
    return GeneratePreset(
      id: src['id']?.toString() ?? '',
      name: src['name']?.toString() ?? '未命名',
      workflowEngine: src['workflowEngine']?.toString() ?? 'sdxl',
      basePrompt: src['basePrompt']?.toString() ?? '',
      negativePrompt: src['negativePrompt']?.toString() ?? '',
      width: (src['width'] as num?)?.toInt() ?? 832,
      height: (src['height'] as num?)?.toInt() ?? 1216,
      steps: (src['steps'] as num?)?.toInt() ?? 6,
      cfg: (src['cfg'] as num?)?.toDouble() ?? 1.0,
      sampler: src['sampler']?.toString() ?? 'euler',
      scheduler: src['scheduler']?.toString() ?? 'simple',
      denoise: (src['denoise'] as num?)?.toDouble() ?? 1.0,
      seed: (src['seed'] as num?)?.toInt() ?? -1,
      checkpointName: src['checkpointName']?.toString() ??
          src['unetName']?.toString() ??
          '',
      unetName: src['unetName']?.toString() ?? '',
      clipName: src['clipName']?.toString() ?? '',
      clipType: src['clipType']?.toString() ?? '',
      vaeName: src['vaeName']?.toString() ?? '',
      loras: loraRaw is List
          ? loraRaw
              .whereType<Map>()
              .map((e) => LoraConfig.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      enableHires: src['enableHires'] == true,
      hiresWidth: (src['hiresWidth'] as num?)?.toInt() ?? 1080,
      hiresHeight: (src['hiresHeight'] as num?)?.toInt() ?? 1920,
      hiresDenoise: (src['hiresDenoise'] as num?)?.toDouble() ?? 0.4,
      hiresSteps: (src['hiresSteps'] as num?)?.toInt() ?? 20,
      enableUpscale: src['enableUpscale'] == true,
      upscaleModel: src['upscaleModel']?.toString() ?? '',
      samplerOptions: (src['samplerOptions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      schedulerOptions: (src['schedulerOptions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'workflowEngine': workflowEngine,
        'basePrompt': basePrompt,
        'negativePrompt': negativePrompt,
        'width': width,
        'height': height,
        'steps': steps,
        'cfg': cfg,
        'sampler': sampler,
        'scheduler': scheduler,
        'denoise': denoise,
        'seed': seed,
        'checkpointName': checkpointName,
        if (unetName.isNotEmpty) 'unetName': unetName,
        if (clipName.isNotEmpty) 'clipName': clipName,
        if (clipType.isNotEmpty) 'clipType': clipType,
        if (vaeName.isNotEmpty) 'vaeName': vaeName,
        'loras': loras.map((e) => e.toJson()).toList(),
        'enableHires': enableHires,
        'hiresWidth': hiresWidth,
        'hiresHeight': hiresHeight,
        'hiresDenoise': hiresDenoise,
        'hiresSteps': hiresSteps,
        'enableUpscale': enableUpscale,
        'upscaleModel': upscaleModel,
        if (samplerOptions.isNotEmpty) 'samplerOptions': samplerOptions,
        if (schedulerOptions.isNotEmpty) 'schedulerOptions': schedulerOptions,
      };

  /// Overrides sent with generate (same keys Web uses).
  Map<String, dynamic> toOverrides() => {
        'basePrompt': basePrompt,
        'negativePrompt': negativePrompt,
        'width': width,
        'height': height,
        'steps': steps,
        'cfg': cfg,
        'sampler': sampler,
        'scheduler': scheduler,
        'checkpointName': checkpointName,
        'enableUpscale': enableUpscale,
        'upscaleModel': upscaleModel,
        'enableHires': enableHires,
        'loras': loras.map((e) => e.toJson()).toList(),
      };

  GeneratePreset copyWith({
    String? id,
    String? name,
    String? workflowEngine,
    String? basePrompt,
    String? negativePrompt,
    int? width,
    int? height,
    int? steps,
    double? cfg,
    String? sampler,
    String? scheduler,
    double? denoise,
    int? seed,
    String? checkpointName,
    String? unetName,
    String? clipName,
    String? clipType,
    String? vaeName,
    List<LoraConfig>? loras,
    bool? enableHires,
    int? hiresWidth,
    int? hiresHeight,
    double? hiresDenoise,
    int? hiresSteps,
    bool? enableUpscale,
    String? upscaleModel,
    List<String>? samplerOptions,
    List<String>? schedulerOptions,
  }) {
    return GeneratePreset(
      id: id ?? this.id,
      name: name ?? this.name,
      workflowEngine: workflowEngine ?? this.workflowEngine,
      basePrompt: basePrompt ?? this.basePrompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      width: width ?? this.width,
      height: height ?? this.height,
      steps: steps ?? this.steps,
      cfg: cfg ?? this.cfg,
      sampler: sampler ?? this.sampler,
      scheduler: scheduler ?? this.scheduler,
      denoise: denoise ?? this.denoise,
      seed: seed ?? this.seed,
      checkpointName: checkpointName ?? this.checkpointName,
      unetName: unetName ?? this.unetName,
      clipName: clipName ?? this.clipName,
      clipType: clipType ?? this.clipType,
      vaeName: vaeName ?? this.vaeName,
      loras: loras ?? this.loras,
      enableHires: enableHires ?? this.enableHires,
      hiresWidth: hiresWidth ?? this.hiresWidth,
      hiresHeight: hiresHeight ?? this.hiresHeight,
      hiresDenoise: hiresDenoise ?? this.hiresDenoise,
      hiresSteps: hiresSteps ?? this.hiresSteps,
      enableUpscale: enableUpscale ?? this.enableUpscale,
      upscaleModel: upscaleModel ?? this.upscaleModel,
      samplerOptions: samplerOptions ?? this.samplerOptions,
      schedulerOptions: schedulerOptions ?? this.schedulerOptions,
    );
  }
}

class LoraConfig {
  final String name;
  final double strengthModel;
  final double strengthClip;

  const LoraConfig({
    this.name = '',
    this.strengthModel = 1.0,
    this.strengthClip = 1.0,
  });

  factory LoraConfig.fromJson(Map<String, dynamic> json) {
    return LoraConfig(
      name: json['name']?.toString() ?? '',
      strengthModel: (json['strengthModel'] as num?)?.toDouble() ??
          (json['modelStrength'] as num?)?.toDouble() ??
          1.0,
      strengthClip: (json['strengthClip'] as num?)?.toDouble() ??
          (json['clipStrength'] as num?)?.toDouble() ??
          1.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'strengthModel': strengthModel,
        'strengthClip': strengthClip,
      };

  LoraConfig copyWith({
    String? name,
    double? strengthModel,
    double? strengthClip,
  }) {
    return LoraConfig(
      name: name ?? this.name,
      strengthModel: strengthModel ?? this.strengthModel,
      strengthClip: strengthClip ?? this.strengthClip,
    );
  }
}

class GenerateExpandSettings {
  final String clothingExpandSystem;
  final String clothingExpandUserTemplate;

  const GenerateExpandSettings({
    this.clothingExpandSystem = '',
    this.clothingExpandUserTemplate = '',
  });

  factory GenerateExpandSettings.fromJson(Map<String, dynamic> json) {
    return GenerateExpandSettings(
      clothingExpandSystem: json['clothingExpandSystem']?.toString() ?? '',
      clothingExpandUserTemplate:
          json['clothingExpandUserTemplate']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'clothingExpandSystem': clothingExpandSystem,
        'clothingExpandUserTemplate': clothingExpandUserTemplate,
      };

  GenerateExpandSettings copyWith({
    String? clothingExpandSystem,
    String? clothingExpandUserTemplate,
  }) {
    return GenerateExpandSettings(
      clothingExpandSystem: clothingExpandSystem ?? this.clothingExpandSystem,
      clothingExpandUserTemplate:
          clothingExpandUserTemplate ?? this.clothingExpandUserTemplate,
    );
  }
}
