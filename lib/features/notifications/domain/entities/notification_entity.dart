import 'package:equatable/equatable.dart';

class NotificationEntity extends Equatable {
  const NotificationEntity({
    required this.id,
    required this.userId,
    required this.type,
    required this.createdAt,
    this.actorId,
    this.title,
    this.body,
    this.productId,
    this.readAt,
  });

  final String id;
  final String userId;
  final String? actorId;
  final String type;
  final String? title;
  final String? body;
  final String? productId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  @override
  List<Object?> get props =>
      [id, userId, actorId, type, title, body, productId, readAt, createdAt];
}
