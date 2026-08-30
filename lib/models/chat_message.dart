enum MessageRole { user, assistant }

enum ImageStatus { none, queued, running, done, error }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final String? imageUrl;
  final ImageStatus imageStatus;
  final String? imageError;
  final String? imageJobId;
  final String? emotionAnalysis;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.imageUrl,
    this.imageStatus = ImageStatus.none,
    this.imageError,
    this.imageJobId,
    this.emotionAnalysis,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
      role: json['role'] == 'user' ? MessageRole.user : MessageRole.assistant,
      content: json['content']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString(),
      imageStatus: _parseImageStatus(json['imageStatus']?.toString()),
      imageError: json['imageError']?.toString(),
      imageJobId: json['imageJobId']?.toString(),
      emotionAnalysis: json['emotionAnalysis']?.toString() ??
          (json['emotionAnalysis'] is Map
              ? (json['emotionAnalysis'] as Map).toString()
              : null),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (json['timestamp'] as num?)?.toInt() ??
            DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static ImageStatus _parseImageStatus(String? s) {
    switch (s) {
      case 'queued':
        return ImageStatus.queued;
      case 'running':
      case 'generating':
        return ImageStatus.running;
      case 'done':
      case 'completed':
        return ImageStatus.done;
      case 'error':
      case 'failed':
        return ImageStatus.error;
      default:
        return ImageStatus.none;
    }
  }

  ChatMessage copyWith({
    String? id,
    MessageRole? role,
    String? content,
    String? imageUrl,
    ImageStatus? imageStatus,
    String? imageError,
    String? imageJobId,
    String? emotionAnalysis,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      imageStatus: imageStatus ?? this.imageStatus,
      imageError: imageError ?? this.imageError,
      imageJobId: imageJobId ?? this.imageJobId,
      emotionAnalysis: emotionAnalysis ?? this.emotionAnalysis,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
