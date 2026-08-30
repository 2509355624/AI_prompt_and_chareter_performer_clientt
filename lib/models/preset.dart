class GeneratePreset {
  final String id;
  final String name;
  final String basePrompt;
  final String stylePrefix;
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
  final List<LoraConfig> loras;

  GeneratePreset({
    required this.id,
    required this.name,
    this.basePrompt = '',
    this.stylePrefix = '',
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
    this.loras = const [],
  });

  factory GeneratePreset.fromJson(Map<String, dynamic> json) {
    final content = json['content'] as Map<String, dynamic>? ?? {};
    return GeneratePreset(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名',
      basePrompt: content['basePrompt']?.toString() ?? '',
      stylePrefix: content['stylePrefix']?.toString() ?? '',
      negativePrompt: content['negativePrompt']?.toString() ?? '',
      width: (content['width'] as num?)?.toInt() ?? 832,
      height: (content['height'] as num?)?.toInt() ?? 1216,
      steps: (content['steps'] as num?)?.toInt() ?? 6,
      cfg: (content['cfg'] as num?)?.toDouble() ?? 1.0,
      sampler: content['sampler']?.toString() ?? 'euler',
      scheduler: content['scheduler']?.toString() ?? 'simple',
      denoise: (content['denoise'] as num?)?.toDouble() ?? 1.0,
      seed: (content['seed'] as num?)?.toInt() ?? -1,
      checkpointName: content['checkpointName']?.toString() ?? '',
      loras: (content['loras'] as List?)
              ?.map((e) => LoraConfig.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class LoraConfig {
  final String name;
  final double modelStrength;
  final double clipStrength;

  LoraConfig({
    required this.name,
    this.modelStrength = 1.0,
    this.clipStrength = 1.0,
  });

  factory LoraConfig.fromJson(Map<String, dynamic> json) {
    return LoraConfig(
      name: json['name']?.toString() ?? '',
      modelStrength: (json['modelStrength'] as num?)?.toDouble() ?? 1.0,
      clipStrength: (json['clipStrength'] as num?)?.toDouble() ?? 1.0,
    );
  }
}
