import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../product/data/models/product_model.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<SellerProfileEntity?> getSellerProfile(String sellerId,
      {String? currentUserId}) async {
    // Явный список колонок — совместимость со старой схемой без following_count, is_verified
    final userRes = await _client
        .from(SupabaseConstants.usersTable)
        .select('id, name, avatar, bio, followers_count')
        .eq('id', sellerId)
        .maybeSingle();
    if (userRes == null) return null;
    final userMap = Map<String, dynamic>.from(userRes as Map);
    final productsRes = await _client
        .from(SupabaseConstants.productsTable)
        .select('*, users!seller_id(name, avatar)')
        .eq('seller_id', sellerId)
        .order('created_at', ascending: false);
    final products = (productsRes as List)
        .map((e) => _mapProduct(e as Map<String, dynamic>))
        .toList();
    bool isFollowingByMe = false;
    if (currentUserId != null && currentUserId != sellerId) {
      final f = await _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', currentUserId)
          .eq('following_id', sellerId)
          .maybeSingle();
      isFollowingByMe = f != null;
    }
    return SellerProfileEntity(
      id: userMap['id'] as String,
      name: userMap['name'] as String? ?? 'Seller',
      avatarUrl: userMap['avatar'] as String?,
      bio: userMap['bio'] as String?,
      followersCount: userMap['followers_count'] as int? ?? 0,
      followingCount: userMap['following_count'] as int? ?? 0,
      isFollowingByMe: isFollowingByMe,
      products: products,
      isVerified: userMap['is_verified'] as bool? ?? false,
    );
  }

  @override
  Future<List<SellerProfileEntity>> getVerifiedUsers() async {
    try {
      final res = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar, bio, followers_count, following_count, is_verified')
          .eq('is_verified', true)
          .order('followers_count', ascending: false);
      final list = res as List;
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        return SellerProfileEntity(
          id: m['id'] as String,
          name: m['name'] as String? ?? 'Official',
          avatarUrl: m['avatar'] as String?,
          bio: m['bio'] as String?,
          followersCount: m['followers_count'] as int? ?? 0,
          followingCount: m['following_count'] as int? ?? 0,
          isFollowingByMe: false,
          products: const [],
          isVerified: true,
        );
      }).toList();
    } on PostgrestException catch (_) {
      // Колонка is_verified или following_count ещё не добавлена в БД
      return [];
    }
  }

  @override
  Future<void> toggleFollow(String followerId, String followingId) async {
    final existing = await _client
        .from(SupabaseConstants.followersTable)
        .select('follower_id')
        .eq('follower_id', followerId)
        .eq('following_id', followingId)
        .maybeSingle();
    if (existing != null) {
      await _client
          .from(SupabaseConstants.followersTable)
          .delete()
          .eq('follower_id', followerId)
          .eq('following_id', followingId);
    } else {
      await _client.from(SupabaseConstants.followersTable).insert({
        'follower_id': followerId,
        'following_id': followingId,
      });
    }
  }

  @override
  Future<void> updateProfile({
    required String userId,
    String? name,
    String? avatarUrl,
    String? bio,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (avatarUrl != null) updates['avatar'] = avatarUrl;
    if (bio != null) updates['bio'] = bio;
    if (updates.isEmpty) return;
    updates['updated_at'] = DateTime.now().toIso8601String();
    await _client
        .from(SupabaseConstants.usersTable)
        .update(updates)
        .eq('id', userId);
  }

  ProductModel _mapProduct(Map<String, dynamic> json) {
    final users = json['users'];
    Map<String, dynamic>? userMap;
    if (users is Map) {
      userMap = Map<String, dynamic>.from(users);
    }
    final row = Map<String, dynamic>.from(json)
      ..remove('users')
      ..['seller_name'] = userMap?['name']
      ..['seller_avatar'] = userMap?['avatar'];
    return ProductModel.fromJson(row);
  }
}
