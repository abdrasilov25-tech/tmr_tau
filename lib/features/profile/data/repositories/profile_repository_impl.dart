import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../product/data/models/product_model.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  ProfileRepositoryImpl(this._client);
  final SupabaseClient _client;

  Future<int> _sumLikesFromPosts(String userId) async {
    try {
      final res = await _client
          .from(SupabaseConstants.postsTable)
          .select('likes_count')
          .eq('user_id', userId);
      var sum = 0;
      for (final e in res as List) {
        final m = Map<String, dynamic>.from(e as Map);
        sum += (m['likes_count'] as int? ?? 0);
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  @override
  Future<SellerProfileEntity?> getSellerProfile(String sellerId,
      {String? currentUserId}) async {
    late final Map<String, dynamic> userMap;
    var totalReceivedPostLikes = 0;
    try {
      final userRes = await _client
          .from(SupabaseConstants.usersTable)
          .select(
            'id, name, avatar, bio, followers_count, is_verified, official_page_active, seller_verified_store, total_received_post_likes, instagram_url, telegram_username, website_url',
          )
          .eq('id', sellerId)
          .maybeSingle();
      if (userRes == null) return null;
      userMap = Map<String, dynamic>.from(userRes as Map);
      final v = userMap['total_received_post_likes'];
      if (v is int) {
        totalReceivedPostLikes = v;
      } else if (v is num) {
        totalReceivedPostLikes = v.toInt();
      }
    } on PostgrestException catch (_) {
      try {
        final userRes = await _client
            .from(SupabaseConstants.usersTable)
            .select('id, name, avatar, bio, followers_count, is_verified, official_page_active, seller_verified_store, instagram_url, telegram_username, website_url')
            .eq('id', sellerId)
            .maybeSingle();
        if (userRes == null) return null;
        userMap = Map<String, dynamic>.from(userRes as Map);
        totalReceivedPostLikes = await _sumLikesFromPosts(sellerId);
      } on PostgrestException catch (_) {
        // Совместимость со старой схемой БД без части полей монетизации.
        final userRes = await _client
            .from(SupabaseConstants.usersTable)
            .select('id, name, avatar, bio, followers_count, is_verified, instagram_url, telegram_username, website_url')
            .eq('id', sellerId)
            .maybeSingle();
        if (userRes == null) return null;
        userMap = Map<String, dynamic>.from(userRes as Map)
          ..putIfAbsent('official_page_active', () => false)
          ..putIfAbsent('seller_verified_store', () => false);
        totalReceivedPostLikes = await _sumLikesFromPosts(sellerId);
      }
    }

    var followersCount = userMap['followers_count'] as int? ?? 0;
    var followingCount = 0;
    var products = <ProductModel>[];
    var isFollowingByMe = false;
    try {
      // Считаем количество подписчиков и подписок на основе таблицы followers,
      // чтобы цифры всегда были актуальными.
      final followersRes = await _client
          .from(SupabaseConstants.followersTable)
          .select('follower_id')
          .eq('following_id', sellerId);
      final followingRes = await _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', sellerId);
      followersCount = (followersRes as List).length;
      followingCount = (followingRes as List).length;
    } catch (_) {
      followingCount = 0;
    }
    try {
      final productsRes = await _client
          .from(SupabaseConstants.productsTable)
          .select('*, users!seller_id(name, avatar)')
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false);
      products = (productsRes as List)
          .map((e) => _mapProduct(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      products = const <ProductModel>[];
    }
    if (currentUserId != null && currentUserId != sellerId) {
      try {
        final f = await _client
            .from(SupabaseConstants.followersTable)
            .select('following_id')
            .eq('follower_id', currentUserId)
            .eq('following_id', sellerId)
            .maybeSingle();
        isFollowingByMe = f != null;
      } catch (_) {
        isFollowingByMe = false;
      }
    }
    final resolvedVerified = (userMap['is_verified'] as bool? ?? false) ||
        (userMap['official_page_active'] as bool? ?? false) ||
        (userMap['seller_verified_store'] as bool? ?? false);

    return SellerProfileEntity(
      id: userMap['id'] as String,
      name: userMap['name'] as String? ?? 'Seller',
      avatarUrl: userMap['avatar'] as String?,
      bio: userMap['bio'] as String?,
      followersCount: followersCount,
      followingCount: followingCount,
      totalReceivedPostLikes: totalReceivedPostLikes,
      isFollowingByMe: isFollowingByMe,
      products: products,
      isVerified: resolvedVerified,
      instagramUrl: userMap['instagram_url'] as String?,
      telegramUsername: userMap['telegram_username'] as String?,
      websiteUrl: userMap['website_url'] as String?,
    );
  }

  @override
  Future<List<SellerProfileEntity>> getVerifiedUsers() async {
    try {
      final res = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar, bio, followers_count, following_count, is_verified, official_page_active, seller_verified_store')
          .or(
            'is_verified.eq.true,official_page_active.eq.true,seller_verified_store.eq.true',
          )
          .order('followers_count', ascending: false);
      final list = res as List;
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final resolvedVerified = (m['is_verified'] as bool? ?? false) ||
            (m['official_page_active'] as bool? ?? false) ||
            (m['seller_verified_store'] as bool? ?? false);
        return SellerProfileEntity(
          id: m['id'] as String,
          name: m['name'] as String? ?? 'Official',
          avatarUrl: m['avatar'] as String?,
          bio: m['bio'] as String?,
          followersCount: m['followers_count'] as int? ?? 0,
          followingCount: m['following_count'] as int? ?? 0,
          totalReceivedPostLikes: 0,
          isFollowingByMe: false,
          products: const [],
          isVerified: resolvedVerified,
        );
      }).toList();
    } on PostgrestException catch (_) {
      // Колонка is_verified или following_count ещё не добавлена в БД
      return [];
    }
  }

  @override
  Future<List<SellerProfileEntity>> searchUsers(String query,
      {int limit = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    // Экранируем кавычку; в Postgrest ilike принимает паттерн с %
    final safe = q.replaceAll(r"'", r"''");
    try {
      // Поиск по имени и по bio (как в Instagram). is_verified может отсутствовать в БД.
      final res = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar, bio, followers_count, is_verified, official_page_active, seller_verified_store')
          .or(
            'name.ilike.%$safe%,bio.ilike.%$safe%,telegram_username.ilike.%$safe%',
          )
          .order('followers_count', ascending: false)
          .limit(limit);
      final list = res as List;
      return list.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final name = m['name'] ?? m['Name'];
        final resolvedVerified = (m['is_verified'] ?? m['isVerified']) as bool? ?? false ||
            (m['official_page_active'] as bool? ?? false) ||
            (m['seller_verified_store'] as bool? ?? false);
        return SellerProfileEntity(
          id: m['id'] as String,
          name: name != null ? name.toString() : 'Пользователь',
          avatarUrl: (m['avatar'] ?? m['Avatar']) as String?,
          bio: (m['bio'] ?? m['Bio']) as String?,
          followersCount: m['followers_count'] as int? ?? 0,
          followingCount: 0,
          totalReceivedPostLikes: 0,
          isFollowingByMe: false,
          products: const [],
          isVerified: resolvedVerified,
        );
      }).toList();
    } on PostgrestException catch (e) {
      // ignore: avoid_print
      print('searchUsers PostgrestException: ${e.message}');
      return [];
    }
  }

  @override
  Future<List<SellerProfileEntity>> getFollowingUsers(String followerId) async {
    // Сначала берём всех, на кого подписан пользователь.
    final followersRes = await _client
        .from(SupabaseConstants.followersTable)
        .select('following_id')
        .eq('follower_id', followerId);
    final followersList = followersRes as List;
    if (followersList.isEmpty) return [];

    final followingIds = followersList
        .map((e) => (e as Map)['following_id'] as String)
        .toSet()
        .toList();

    // Для простоты и совместимости без in_ загружаем пользователей по одному.
    final List<SellerProfileEntity> result = [];
    for (final id in followingIds) {
      final userRes = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar, bio, followers_count, is_verified, official_page_active, seller_verified_store')
          .eq('id', id)
          .maybeSingle();
      if (userRes == null) continue;
      final m = Map<String, dynamic>.from(userRes as Map);
      final resolvedVerified = (m['is_verified'] as bool? ?? false) ||
          (m['official_page_active'] as bool? ?? false) ||
          (m['seller_verified_store'] as bool? ?? false);
      result.add(
        SellerProfileEntity(
          id: m['id'] as String,
          name: m['name'] as String? ?? 'User',
          avatarUrl: m['avatar'] as String?,
          bio: m['bio'] as String?,
          followersCount: m['followers_count'] as int? ?? 0,
          followingCount: 0,
          totalReceivedPostLikes: 0,
          isFollowingByMe: true,
          products: const [],
          isVerified: resolvedVerified,
        ),
      );
    }
    return result;
  }

  @override
  Future<List<SellerProfileEntity>> getFollowersUsers(String followingId) async {
    // Все, кто подписаны на данного пользователя.
    final res = await _client
        .from(SupabaseConstants.followersTable)
        .select('follower_id')
        .eq('following_id', followingId);
    final list = res as List;
    if (list.isEmpty) return [];

    final followerIds = list
        .map((e) => (e as Map)['follower_id'] as String)
        .toSet()
        .toList();

    final myFollowingRes = await _client
        .from(SupabaseConstants.followersTable)
        .select('following_id')
        .eq('follower_id', followingId);
    final myFollowingIds = (myFollowingRes as List)
        .map((e) => (e as Map)['following_id'] as String)
        .toSet();

    final List<SellerProfileEntity> result = [];
    for (final id in followerIds) {
      final userRes = await _client
          .from(SupabaseConstants.usersTable)
          .select('id, name, avatar, bio, followers_count, is_verified, official_page_active, seller_verified_store')
          .eq('id', id)
          .maybeSingle();
      if (userRes == null) continue;
      final m = Map<String, dynamic>.from(userRes as Map);
      final resolvedVerified = (m['is_verified'] as bool? ?? false) ||
          (m['official_page_active'] as bool? ?? false) ||
          (m['seller_verified_store'] as bool? ?? false);
      result.add(
        SellerProfileEntity(
          id: m['id'] as String,
          name: m['name'] as String? ?? 'User',
          avatarUrl: m['avatar'] as String?,
          bio: m['bio'] as String?,
          followersCount: m['followers_count'] as int? ?? 0,
          followingCount: 0,
          totalReceivedPostLikes: 0,
          isFollowingByMe: myFollowingIds.contains(id),
          products: const [],
          isVerified: resolvedVerified,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> toggleFollow(String followerId, String followingId) async {
    try {
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
    } on PostgrestException catch (e) {
      if (e.code != '23505') {
        // ignore: avoid_print
        print('Postgrest toggleFollow error: $e');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Unknown toggleFollow error: $e');
    }
  }

  @override
  Future<void> updateProfile({
    required String userId,
    String? name,
    String? avatarUrl,
    String? bio,
    String? username,
    String? gender,
    String? city,
    String? instagramUrl,
    String? telegramUsername,
    String? websiteUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name;
    if (username != null) updates['username'] = username;
    if (avatarUrl != null) updates['avatar'] = avatarUrl;
    if (bio != null) updates['bio'] = bio;
    if (city != null) updates['city'] = city;
    if (instagramUrl != null) updates['instagram_url'] = instagramUrl;
    if (telegramUsername != null) updates['telegram_username'] = telegramUsername;
    if (websiteUrl != null) updates['website_url'] = websiteUrl;
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
