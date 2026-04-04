import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../product/data/models/product_model.dart';
import '../../domain/entities/creator_monthly_stats.dart';
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

    // followers_count уже есть в userMap (денормализованное поле)
    var followersCount = userMap['followers_count'] as int? ?? 0;
    var followingCount = 0;
    var products = <ProductModel>[];
    var isFollowingByMe = false;

    // Оптимизированный продуктовый запрос — только нужные колонки
    const profileProductSelect =
        'id, title, price, image_url, image_urls, category, category_id, '
        'seller_id, created_at, city, condition, is_urgent, is_top, '
        'is_negotiable, is_giveaway, view_count, '
        'users!seller_id(name, avatar)';

    // Параллельно: following_count + товары (до 30) + статус подписки + лучший тап
    final parallelResults = await Future.wait([
      // following_count: только кол-во подписок
      _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', sellerId)
          .limit(2000)
          .then<Object?>((v) => v)
          .catchError((_) => <dynamic>[]),
      // Товары продавца — лимит 30
      _client
          .from(SupabaseConstants.productsTable)
          .select(profileProductSelect)
          .eq('seller_id', sellerId)
          .order('is_top', ascending: false)
          .order('created_at', ascending: false)
          .limit(30)
          .then<Object?>((v) => v)
          .catchError((_) => <dynamic>[]),
      // Статус подписки текущего пользователя
      if (currentUserId != null && currentUserId != sellerId)
        _client
            .from(SupabaseConstants.followersTable)
            .select('following_id')
            .eq('follower_id', currentUserId)
            .eq('following_id', sellerId)
            .maybeSingle()
            .then<Object?>((v) => v)
            .catchError((_) => null)
      else
        Future<Object?>.value(null),
      // Лучший результат в «Тап судьбы»
      _client
          .from('tap_game_plays')
          .select('score')
          .eq('user_id', sellerId)
          .order('score', ascending: false)
          .limit(1)
          .then<Object?>((v) => v)
          .catchError((_) => <dynamic>[]),
    ]);
    // Переименуем для совместимости с кодом ниже
    final secondaryResults = [parallelResults[1], parallelResults[2]];
    followingCount = (parallelResults[0] as List).length;
    final tapPlays = parallelResults[3] as List? ?? [];
    final bestTapScore = tapPlays.isNotEmpty
        ? ((tapPlays.first as Map)['score'] as int? ?? 0)
        : 0;

    try {
      products = (secondaryResults[0] as List)
          .map((e) => _mapProduct(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      products = const <ProductModel>[];
    }
    isFollowingByMe = secondaryResults[1] != null;
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
      officialPageActive: userMap['official_page_active'] as bool? ?? false,
      bestTapScore: bestTapScore,
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
          officialPageActive: m['official_page_active'] as bool? ?? false,
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
          officialPageActive: m['official_page_active'] as bool? ?? false,
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

    // Один батч-запрос вместо N запросов по одному.
    final usersRes = await _client
        .from(SupabaseConstants.usersTable)
        .select('id, name, avatar, bio, followers_count, is_verified, official_page_active, seller_verified_store')
        .inFilter('id', followingIds);

    return (usersRes as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final resolvedVerified = (m['is_verified'] as bool? ?? false) ||
          (m['official_page_active'] as bool? ?? false) ||
          (m['seller_verified_store'] as bool? ?? false);
      return SellerProfileEntity(
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
        officialPageActive: m['official_page_active'] as bool? ?? false,
      );
    }).toList();
  }

  @override
  Future<List<SellerProfileEntity>> getFollowersUsers(String followingId) async {
    // Параллельно грузим подписчиков и список "на кого я подписан" — два запроса вместо N+2.
    final results = await Future.wait([
      _client
          .from(SupabaseConstants.followersTable)
          .select('follower_id')
          .eq('following_id', followingId),
      _client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', followingId),
    ]);

    final followerIds = (results[0] as List)
        .map((e) => (e as Map)['follower_id'] as String)
        .toSet()
        .toList();
    if (followerIds.isEmpty) return [];

    final myFollowingIds = (results[1] as List)
        .map((e) => (e as Map)['following_id'] as String)
        .toSet();

    // Один батч-запрос для всех профилей.
    final usersRes = await _client
        .from(SupabaseConstants.usersTable)
        .select('id, name, avatar, bio, followers_count, is_verified, official_page_active, seller_verified_store')
        .inFilter('id', followerIds);

    return (usersRes as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final id = m['id'] as String;
      final resolvedVerified = (m['is_verified'] as bool? ?? false) ||
          (m['official_page_active'] as bool? ?? false) ||
          (m['seller_verified_store'] as bool? ?? false);
      return SellerProfileEntity(
        id: id,
        name: m['name'] as String? ?? 'User',
        avatarUrl: m['avatar'] as String?,
        bio: m['bio'] as String?,
        followersCount: m['followers_count'] as int? ?? 0,
        followingCount: 0,
        totalReceivedPostLikes: 0,
        isFollowingByMe: myFollowingIds.contains(id),
        products: const [],
        isVerified: resolvedVerified,
        officialPageActive: m['official_page_active'] as bool? ?? false,
      );
    }).toList();
  }

  @override
  Future<CreatorMonthlyStats> getCreatorMonthlyStats() async {
    try {
      final raw = await _client.rpc<dynamic>('get_creator_monthly_stats');
      if (raw is! Map) {
        return const CreatorMonthlyStats(eligible: false);
      }
      final m = Map<String, dynamic>.from(raw);
      final eligible = m['eligible'] == true;
      final periodDays = (m['period_days'] as num?)?.toInt() ?? 30;
      if (!eligible) {
        return CreatorMonthlyStats(
          eligible: false,
          periodDays: periodDays,
        );
      }
      return CreatorMonthlyStats(
        eligible: true,
        periodDays: periodDays,
        profileViews: (m['profile_views'] as num?)?.toInt() ?? 0,
        interactions: (m['interactions'] as num?)?.toInt() ?? 0,
        newFollowers: (m['new_followers'] as num?)?.toInt() ?? 0,
        sharedPosts: (m['shared_posts'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const CreatorMonthlyStats(eligible: false);
    }
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
        // Уведомление автору профиля о новом подписчике
        try {
          await _client.from('notifications').insert({
            'user_id': followingId,
            'actor_id': followerId,
            'type': 'follow',
            'title': 'Новый подписчик',
            'body': 'Подписался на вас',
          });
        } catch (_) {}
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
