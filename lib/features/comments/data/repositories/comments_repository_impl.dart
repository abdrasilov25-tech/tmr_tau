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
    try {
      final res = await _client
          .from(SupabaseConstants.productCommentsTable)
          .select('*, users!user_id(name, avatar)')
          .eq('product_id', productId)
          .order('created_at', ascending: true);
      return (res as List).map((e) => _mapComment(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // Fallback: load without join (e.g. if RLS blocks users or relation name differs)
      final res = await _client
          .from(SupabaseConstants.productCommentsTable)
          .select()
          .eq('product_id', productId)
          .order('created_at', ascending: true);
      return (res as List).map((e) => _mapComment(e as Map<String, dynamic>)).toList();
    }
  }

  @override
  Future<void> addComment({
    required String productId,
    required String userId,
    required String text,
  }) async {
    final inserted = await _client
        .from(SupabaseConstants.productCommentsTable)
        .insert({
          'product_id': productId,
          'user_id': userId,
          'text': text,
        })
        .select('id')
        .single();
    final commentId = inserted['id'] as String;
    await _notifySellerProductComment(
      productId: productId,
      actorId: userId,
      text: text,
      commentId: commentId,
    );
  }

  Future<void> _notifySellerProductComment({
    required String productId,
    required String actorId,
    required String text,
    required String commentId,
  }) async {
    final row = await _client
        .from(SupabaseConstants.productsTable)
        .select('seller_id')
        .eq('id', productId)
        .maybeSingle();
    if (row == null) return;
    final sellerId = row['seller_id'] as String?;
    if (sellerId == null || sellerId == actorId) return;
    final body = text.trim().isEmpty
        ? 'Новый комментарий к объявлению'
        : 'Комментарий: ${text.trim()}';
    await _client.from(SupabaseConstants.notificationsTable).insert({
      'user_id': sellerId,
      'actor_id': actorId,
      'type': 'product_comment',
      'title': 'Комментарий к объявлению',
      'body': body,
      'product_id': productId,
      'comment_id': commentId,
    });
  }

  @override
  Future<void> toggleProductCommentLike(String commentId, String userId) async {
    final existing = await _client
        .from(SupabaseConstants.productCommentLikesTable)
        .select('comment_id')
        .eq('comment_id', commentId)
        .eq('user_id', userId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.productCommentLikesTable)
          .delete()
          .eq('comment_id', commentId)
          .eq('user_id', userId);
    } else {
      await _client.from(SupabaseConstants.productCommentLikesTable).insert({
        'comment_id': commentId,
        'user_id': userId,
      });
    }
  }

  @override
  Future<bool> isProductCommentLikedOwn(String commentId, String userId) async {
    final row = await _client
        .from(SupabaseConstants.productCommentLikesTable)
        .select('comment_id')
        .eq('comment_id', commentId)
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
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
