import '../../domain/entities/product_comment_entity.dart';

class ProductCommentModel extends ProductCommentEntity {
  const ProductCommentModel({
    required super.id,
    required super.productId,
    required super.userId,
    required super.text,
    required super.createdAt,
    super.userName,
    super.userAvatarUrl,
  });

  factory ProductCommentModel.fromJson(Map<String, dynamic> json) {
    return ProductCommentModel(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      userId: json['user_id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
    );
  }
}
