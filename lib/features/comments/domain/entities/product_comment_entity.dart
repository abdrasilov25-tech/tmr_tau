import 'package:equatable/equatable.dart';

class ProductCommentEntity extends Equatable {
  const ProductCommentEntity({
    required this.id,
    required this.productId,
    required this.userId,
    required this.text,
    required this.createdAt,
    this.userName,
    this.userAvatarUrl,
  });

  final String id;
  final String productId;
  final String userId;
  final String text;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatarUrl;

  @override
  List<Object?> get props =>
      [id, productId, userId, text, createdAt, userName, userAvatarUrl];
}
