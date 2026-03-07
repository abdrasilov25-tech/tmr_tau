import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/product_comment_entity.dart';
import '../../domain/repositories/comments_repository.dart';
import '../models/product_comment_model.dart';

class CommentsRepositoryImpl implements CommentsRepository {
  CommentsRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<List<ProductCommentEntity>> getProductComments(
      String productId) async {
    final res = await _client
        .from(SupabaseConstants.productCommentsTable)
        .select('*, users!user_id(name, avatar)')
        .eq('product_id', productId)
        .order('created_at', ascending: true);
    return (res as List).map((e) => _mapComment(e as Map<String, dynamic>)).toList();
  }

  @override
  Future<ProductCommentEntity> addComment({
    required String productId,
    required String userId,
    required String text,
  }) async {
    final res = await _client
        .from(SupabaseConstants.productCommentsTable)
        .insert({'product_id': productId, 'user_id': userId, 'text': text})
        .select('*, users!user_id(name, avatar)')
        .single();
    return _mapComment(Map<String, dynamic>.from(res as Map));
  }

  @override
  Future<void> deleteComment(String commentId, String userId) async {
    await _client
        .from(SupabaseConstants.productCommentsTable)
        .delete()
        .eq('id', commentId)
        .eq('user_id', userId);
  }

  ProductCommentEntity _mapComment(Map<String, dynamic> json) {
    final users = json['users'];
    Map<String, dynamic>? u;
    if (users is Map) u = Map<String, dynamic>.from(users);
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..['user_name'] = u?['name']
      ..['user_avatar'] = u?['avatar'];
    return ProductCommentModel.fromJson(row);
  }
}
