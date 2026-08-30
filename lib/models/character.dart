class Character {
  final String id;
  final String name;
  final String description;
  final String avatar; // emoji 或 URL
  final String personality;
  final String systemPrompt;
  final String appearancePrompt;
  final String outfitPrompt;
  final String referenceImage;
  final int createdAt;

  Character({
    required this.id,
    required this.name,
    this.description = '',
    this.avatar = '👤',
    this.personality = '',
    this.systemPrompt = '',
    this.appearancePrompt = '',
    this.outfitPrompt = '',
    this.referenceImage = '',
    this.createdAt = 0,
  });

  factory Character.fromJson(Map<String, dynamic> json) {
    return Character(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名角色',
      description: json['description']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '👤',
      personality: json['personality']?.toString() ?? '',
      systemPrompt: json['systemPrompt']?.toString() ?? '',
      appearancePrompt: json['appearancePrompt']?.toString() ?? '',
      outfitPrompt: json['outfitPrompt']?.toString() ?? '',
      referenceImage: json['referenceImage']?.toString() ?? '',
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'avatar': avatar,
      'personality': personality,
      'systemPrompt': systemPrompt,
      'appearancePrompt': appearancePrompt,
      'outfitPrompt': outfitPrompt,
      'referenceImage': referenceImage,
      'createdAt': createdAt,
    };
  }
}
