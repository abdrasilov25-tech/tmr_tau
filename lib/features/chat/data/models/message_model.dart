import 'package:equatable/equatable.dart';

/// Тип сообщения в чате.
enum MessageType { text, audio, videoCircle }

class MessageEntity extends Equatable {
  const MessageEntity({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    required this.createdAt,
    this.messageType = MessageType.text,
    this.audioUrl,
    this.videoUrl,
    this.durationSeconds,
  });

  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final DateTime createdAt;
  final MessageType messageType;
  final String? audioUrl;
  final String? videoUrl;
  final int? durationSeconds;

  @override
  List<Object?> get props => [
        id,
        senderId,
        receiverId,
        text,
        createdAt,
        messageType,
        audioUrl,
        videoUrl,
        durationSeconds,
      ];
}

class MessageModel extends MessageEntity {
  const MessageModel({
    required super.id,
    required super.senderId,
    required super.receiverId,
    required super.text,
    required super.createdAt,
    super.messageType,
    super.audioUrl,
    super.videoUrl,
    super.durationSeconds,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    final typeStr = (json['message_type'] as String?) ?? 'text';
    final type = switch (typeStr) {
      'audio' => MessageType.audio,
      'video_circle' => MessageType.videoCircle,
      _ => MessageType.text,
    };
    return MessageModel(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      text: (json['text'] as String?) ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      messageType: type,
      audioUrl: json['audio_url'] as String?,
      videoUrl: json['video_url'] as String?,
      durationSeconds: json['duration_seconds'] as int?,
    );
  }

  static MessageType _typeFromRaw(Map<String, dynamic> raw) {
    final t = (raw['message_type'] as String?) ?? 'text';
    return switch (t) {
      'audio' => MessageType.audio,
      'video_circle' => MessageType.videoCircle,
      _ => MessageType.text,
    };
  }

  /// Создаёт [MessageModel] из сырого Map Supabase стрима (без fromJson overhead).
  static MessageModel fromRaw(Map<String, dynamic> raw) => MessageModel(
        id: raw['id'] as String,
        senderId: raw['sender_id'] as String,
        receiverId: raw['receiver_id'] as String,
        text: (raw['text'] as String?) ?? '',
        createdAt: DateTime.parse(raw['created_at'] as String),
        messageType: _typeFromRaw(raw),
        audioUrl: raw['audio_url'] as String?,
        videoUrl: raw['video_url'] as String?,
        durationSeconds: raw['duration_seconds'] as int?,
      );
}
