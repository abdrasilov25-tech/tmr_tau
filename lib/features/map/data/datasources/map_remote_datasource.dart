import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/featured_seller.dart';
import '../../domain/entities/map_leaderboard_entry.dart';
import '../../domain/entities/map_quest.dart';
import '../../domain/entities/map_zone.dart';
import '../../domain/entities/mystery_spot.dart';
import '../models/map_product_model.dart';

abstract class MapRemoteDataSource {
  Future<List<MapProductModel>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  });

  /// Purchases a map boost for [productId] using Qarmet balance.
  /// Returns the new Qarmet balance on success.
  /// Throws [MapBoostException] on failure.
  Future<int> purchaseMapBoost({
    required String productId,
    required int boostLevel,
    required int durationHours,
  });

  /// Returns today's featured seller (highest bidder), or null if no bids yet.
  Future<FeaturedSeller?> getTodayFeatured();

  /// Returns all currently active map zones.
  Future<List<MapZone>> getActiveZones();

  // MAP-5: Sticker Packs
  Future<List<String>> getMyOwnedPackIds();
  Future<int> purchaseStickerPack(String packId);
  Future<void> setProductMarkerSticker(String productId, String? sticker);

  // MAP-3: Leaderboard
  Future<List<MapLeaderboardEntry>> getMapLeaderboard();
  Future<List<MapLeaderboardEntry>> getFriendLeaderboard();

  // MAP-6: Mystery Spot
  Future<MysterySpot?> getTodayMysterySpot({
    required double latitude,
    required double longitude,
  });
  Future<MysterySpotRevealResult> revealMysterySpot(String spotId);
  Future<({String spotId, int newBalance, String spotDate})> purchaseMysterySpotSlot({
    required String offerText,
    required String productId,
    required int bidAmount,
  });

  /// Purchases a geo-zone. Returns new Qarmet balance on success.
  /// Throws [ZonePurchaseException] on failure.
  Future<({String zoneId, int newBalance})> purchaseMapZone({
    required String name,
    required String description,
    required String offerText,
    required Color brandColor,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    required int durationDays,
  });

  /// Returns today's quest progress for the current user.
  Future<MapQuestProgress> getTodayQuestProgress();

  /// Completes a quest and awards Qarmet. Returns (qarmetAwarded, newBalance).
  /// Returns (0, currentBalance) if already completed today.
  /// Throws [QuestException] on failure.
  Future<({int qarmetAwarded, int newBalance, bool alreadyDone})> completeMapQuest(
    MapQuestId questId,
  );

  /// Places or upgrades today's bid for Featured Seller slot.
  /// Returns the new Qarmet balance on success.
  /// Throws [FeaturedBidException] on failure.
  Future<({int newBalance, int bidAmount})> placeFeaturedBid(int bidAmount);
}

class MysterySpotException implements Exception {
  const MysterySpotException(this.code, {this.min, this.required, this.balance});
  final String code;
  final int? min;
  final int? required;
  final int? balance;

  String get userMessage => switch (code) {
        'slot_taken' => 'Слот на завтра уже занят другим продавцом.',
        'bid_too_low' => 'Минимальная ставка: $min Qarmet.',
        'insufficient_balance' =>
          'Недостаточно Qarmet. Нужно $required, у вас $balance.',
        'product_not_found' => 'Объявление не найдено или вы не его владелец.',
        _ => 'Не удалось купить слот. Попробуйте позже.',
      };
}

class StickerPackException implements Exception {
  const StickerPackException(this.code, {this.required, this.balance});
  final String code;
  final int? required;
  final int? balance;
  String get userMessage => switch (code) {
        'insufficient_balance' =>
          'Недостаточно Qarmet. Нужно $required, у вас $balance.',
        _ => 'Не удалось купить пак. Попробуйте позже.',
      };
}

class ZonePurchaseException implements Exception {
  const ZonePurchaseException(this.code, {this.required, this.balance});
  final String code;
  final int? required;
  final int? balance;

  String get userMessage => switch (code) {
        'insufficient_balance' =>
          'Недостаточно Qarmet. Нужно $required, у вас $balance.',
        'unauthenticated' => 'Войдите в аккаунт.',
        _ => 'Не удалось создать зону. Попробуйте позже.',
      };
}

class QuestException implements Exception {
  const QuestException(this.code);
  final String code;

  String get userMessage => switch (code) {
        'quest_pass_required' => 'Этот квест доступен только с Quest Pass.',
        'unauthenticated' => 'Войдите в аккаунт для выполнения квестов.',
        _ => 'Не удалось выполнить квест. Попробуйте позже.',
      };
}

class FeaturedBidException implements Exception {
  const FeaturedBidException(this.code, {this.minRequired, this.topBid, this.required, this.balance});
  final String code;
  final int? minRequired;
  final int? topBid;
  final int? required;
  final int? balance;

  String get userMessage {
    switch (code) {
      case 'bid_too_low':
        return 'Ставка слишком мала. Минимум: $minRequired Qarmet (текущий лидер: $topBid).';
      case 'insufficient_balance':
        return 'Недостаточно Qarmet. Нужно $required, у вас $balance.';
      case 'unauthenticated':
        return 'Войдите в аккаунт, чтобы сделать ставку.';
      default:
        return 'Не удалось разместить ставку. Попробуйте позже.';
    }
  }
}

class MapBoostException implements Exception {
  const MapBoostException(this.code, {this.required, this.balance});
  final String code;
  final int? required;
  final int? balance;

  String get userMessage {
    switch (code) {
      case 'insufficient_balance':
        return 'Недостаточно Qarmet. Нужно $required, у вас $balance.';
      case 'not_owner':
        return 'Вы не являетесь владельцем этого объявления.';
      default:
        return 'Не удалось активировать буст. Попробуйте позже.';
    }
  }
}

class MapRemoteDataSourceImpl implements MapRemoteDataSource {
  MapRemoteDataSourceImpl(this._client);
  final SupabaseClient _client;

  static const _select =
      'id, title, price, image_url, image_urls, city, seller_id, latitude, longitude, is_urgent, is_top, map_boost_level, map_boost_expires_at, map_marker_sticker, users!seller_id(name, avatar)';

  @override
  Future<List<MapProductModel>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) async {
    // Bounding box: 1° latitude ≈ 111 km
    final deltaLat = radiusKm / 111.0;
    final deltaLng =
        radiusKm / (111.0 * math.cos(latitude * math.pi / 180.0));

    final res = await _client
        .from(SupabaseConstants.productsTable)
        .select(_select)
        .not('latitude', 'is', null)
        .not('longitude', 'is', null)
        .gte('latitude', latitude - deltaLat)
        .lte('latitude', latitude + deltaLat)
        .gte('longitude', longitude - deltaLng)
        .lte('longitude', longitude + deltaLng)
        .limit(300);

    final products = (res as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(growable: false);
    final sellerIds = products
        .map((e) => e['seller_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final ratingBySeller = <String, ({double avg, int count})>{};
    if (sellerIds.isNotEmpty) {
      final reviews = await _client
          .from('business_reviews')
          .select('business_user_id,stars')
          .inFilter('business_user_id', sellerIds);
      for (final row in (reviews as List)) {
        final m = row as Map<String, dynamic>;
        final sellerId = m['business_user_id'] as String?;
        final stars = (m['stars'] as num?)?.toDouble();
        if (sellerId == null || stars == null) continue;
        final prev = ratingBySeller[sellerId];
        if (prev == null) {
          ratingBySeller[sellerId] = (avg: stars, count: 1);
        } else {
          final sum = prev.avg * prev.count + stars;
          final count = prev.count + 1;
          ratingBySeller[sellerId] = (avg: sum / count, count: count);
        }
      }
    }

    return products.map((p) {
      final sellerId = p['seller_id'] as String?;
      final rating = sellerId == null ? null : ratingBySeller[sellerId];
      return MapProductModel.fromJson({
        ...p,
        'seller_rating_avg': rating?.avg ?? 0,
        'seller_rating_count': rating?.count ?? 0,
      });
    }).toList(growable: false);
  }

  @override
  Future<int> purchaseMapBoost({
    required String productId,
    required int boostLevel,
    required int durationHours,
  }) async {
    final result = await _client.rpc('purchase_map_boost', params: {
      'p_product_id': productId,
      'p_boost_level': boostLevel,
      'p_duration_hours': durationHours,
    }) as Map<String, dynamic>;

    if (result['success'] != true) {
      throw MapBoostException(
        result['error'] as String? ?? 'unknown',
        required: result['required'] as int?,
        balance: result['balance'] as int?,
      );
    }
    return result['new_balance'] as int;
  }

  @override
  Future<FeaturedSeller?> getTodayFeatured() async {
    final result = await _client.rpc('get_today_featured') as Map<String, dynamic>;
    if (result['found'] != true) return null;
    return FeaturedSeller(
      userId: result['user_id'] as String,
      sellerName: result['seller_name'] as String? ?? 'Продавец',
      sellerAvatarUrl: result['seller_avatar'] as String?,
      bidAmount: result['bid_amount'] as int,
    );
  }

  @override
  Future<List<MapZone>> getActiveZones() async {
    final result = await _client.rpc('get_active_zones') as List;
    return result.map((e) {
      final m = e as Map<String, dynamic>;
      final colorHex = (m['brand_color'] as String? ?? '#2563EB')
          .replaceFirst('#', '');
      final color = Color(int.parse('FF$colorHex', radix: 16));
      return MapZone(
        id: m['id'] as String,
        ownerId: m['owner_id'] as String,
        name: m['name'] as String,
        brandColor: color,
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        radiusMeters: (m['radius_meters'] as num).toInt(),
        activeUntil: DateTime.parse(m['active_until'] as String).toUtc(),
        description: m['description'] as String?,
        offerText: m['offer_text'] as String?,
        ownerAvatarUrl: m['owner_avatar'] as String?,
      );
    }).toList(growable: false);
  }

  @override
  Future<({String zoneId, int newBalance})> purchaseMapZone({
    required String name,
    required String description,
    required String offerText,
    required Color brandColor,
    required double latitude,
    required double longitude,
    required int radiusMeters,
    required int durationDays,
  }) async {
    final hex =
        '#${brandColor.r.round().toRadixString(16).padLeft(2, '0')}${brandColor.g.round().toRadixString(16).padLeft(2, '0')}${brandColor.b.round().toRadixString(16).padLeft(2, '0')}';
    final result = await _client.rpc('purchase_map_zone', params: {
      'p_name': name,
      'p_description': description,
      'p_offer_text': offerText,
      'p_brand_color': hex,
      'p_latitude': latitude,
      'p_longitude': longitude,
      'p_radius_meters': radiusMeters,
      'p_duration_days': durationDays,
    }) as Map<String, dynamic>;

    if (result['success'] != true) {
      throw ZonePurchaseException(
        result['error'] as String? ?? 'unknown',
        required: result['required'] as int?,
        balance: result['balance'] as int?,
      );
    }
    return (
      zoneId: result['zone_id'] as String,
      newBalance: result['new_balance'] as int,
    );
  }

  @override
  Future<MapQuestProgress> getTodayQuestProgress() async {
    final result =
        await _client.rpc('get_today_quest_progress') as Map<String, dynamic>;
    final completions = result['completions'] as List? ?? [];
    final ids = completions
        .map((e) => (e as Map<String, dynamic>)['quest_id'] as String)
        .toSet();
    return MapQuestProgress(
      completedIds: ids,
      totalEarnedToday: (result['total_today'] as num?)?.toInt() ?? 0,
      hasQuestPass: result['quest_pass'] == true,
    );
  }

  @override
  Future<({int qarmetAwarded, int newBalance, bool alreadyDone})> completeMapQuest(
    MapQuestId questId,
  ) async {
    final result = await _client.rpc('complete_map_quest', params: {
      'p_quest_id': questId.rpcId,
    }) as Map<String, dynamic>;

    if (result['success'] != true) {
      throw QuestException(result['error'] as String? ?? 'unknown');
    }
    return (
      qarmetAwarded: (result['qarmet_awarded'] as num?)?.toInt() ?? 0,
      newBalance: (result['new_balance'] as num?)?.toInt() ?? 0,
      alreadyDone: result['already_done'] == true,
    );
  }

  // ---- MAP-5: Sticker Packs ----

  @override
  Future<List<String>> getMyOwnedPackIds() async {
    final result = await _client.rpc('get_my_sticker_packs') as List;
    return result.map((e) => e as String).toList(growable: false);
  }

  @override
  Future<int> purchaseStickerPack(String packId) async {
    final result = await _client.rpc('purchase_sticker_pack', params: {
      'p_pack_id': packId,
    }) as Map<String, dynamic>;
    if (result['success'] != true) {
      throw StickerPackException(
        result['error'] as String? ?? 'unknown',
        required: result['required'] as int?,
        balance: result['balance'] as int?,
      );
    }
    return result['new_balance'] as int;
  }

  @override
  Future<void> setProductMarkerSticker(String productId, String? sticker) async {
    await _client.rpc('set_product_marker_sticker', params: {
      'p_product_id': productId,
      'p_sticker': sticker,
    });
  }

  // ---- MAP-3: Leaderboard ----

  @override
  Future<List<MapLeaderboardEntry>> getMapLeaderboard() async {
    final result = await _client.rpc('get_map_leaderboard') as List;
    return _parseLeaderboard(result);
  }

  @override
  Future<List<MapLeaderboardEntry>> getFriendLeaderboard() async {
    final result = await _client.rpc('get_friend_map_leaderboard') as List;
    return _parseLeaderboard(result);
  }

  // ---- MAP-6: Mystery Spot ----

  @override
  Future<MysterySpot?> getTodayMysterySpot({
    required double latitude,
    required double longitude,
  }) async {
    final result = await _client.rpc('get_today_mystery_spot', params: {
      'p_lat': latitude,
      'p_lng': longitude,
    }) as Map<String, dynamic>?;
    if (result == null) return null;
    return MysterySpot(
      id: result['id'] as String,
      latitude: (result['latitude'] as num).toDouble(),
      longitude: (result['longitude'] as num).toDouble(),
      qarmetReward: (result['qarmet_reward'] as num).toInt(),
      alreadyClaimed: result['already_claimed'] == true,
      isSellerSponsored: result['is_seller_sponsored'] == true,
      sellerName: result['seller_name'] as String?,
      sellerOffer: result['seller_offer'] as String?,
      sellerId: result['seller_id'] as String?,
      productId: result['product_id'] as String?,
    );
  }

  @override
  Future<MysterySpotRevealResult> revealMysterySpot(String spotId) async {
    final result = await _client.rpc('reveal_mystery_spot', params: {
      'p_spot_id': spotId,
    }) as Map<String, dynamic>;
    if (result['success'] != true) {
      throw MysterySpotException(result['error'] as String? ?? 'unknown');
    }
    return MysterySpotRevealResult(
      qarmetAwarded: (result['qarmet_awarded'] as num?)?.toInt() ?? 0,
      newBalance: (result['new_balance'] as num?)?.toInt() ?? 0,
      alreadyClaimed: result['already_claimed'] == true,
      isSellerSponsored: result['is_seller_sponsored'] == true,
      sellerOffer: result['seller_offer'] as String?,
      productId: result['product_id'] as String?,
    );
  }

  @override
  Future<({String spotId, int newBalance, String spotDate})>
      purchaseMysterySpotSlot({
    required String offerText,
    required String productId,
    required int bidAmount,
  }) async {
    final result = await _client.rpc('purchase_mystery_spot_slot', params: {
      'p_offer_text': offerText,
      'p_product_id': productId,
      'p_bid_amount': bidAmount,
    }) as Map<String, dynamic>;
    if (result['success'] != true) {
      throw MysterySpotException(
        result['error'] as String? ?? 'unknown',
        min: result['min'] as int?,
        required: result['required'] as int?,
        balance: result['balance'] as int?,
      );
    }
    return (
      spotId: result['spot_id'] as String,
      newBalance: result['new_balance'] as int,
      spotDate: result['spot_date'] as String,
    );
  }

  List<MapLeaderboardEntry> _parseLeaderboard(List raw) {
    return raw.map((e) {
      final m = e as Map<String, dynamic>;
      return MapLeaderboardEntry(
        userId: m['user_id'] as String,
        userName: m['user_name'] as String? ?? 'Пользователь',
        score: (m['score'] as num).toInt(),
        userAvatarUrl: m['user_avatar'] as String?,
        isMe: m['is_me'] == true,
      );
    }).toList(growable: false);
  }

  @override
  Future<({int newBalance, int bidAmount})> placeFeaturedBid(int bidAmount) async {
    final result = await _client.rpc('place_featured_bid', params: {
      'p_bid_amount': bidAmount,
    }) as Map<String, dynamic>;

    if (result['success'] != true) {
      throw FeaturedBidException(
        result['error'] as String? ?? 'unknown',
        minRequired: result['min_required'] as int?,
        topBid: result['top_bid'] as int?,
        required: result['required'] as int?,
        balance: result['balance'] as int?,
      );
    }
    return (
      newBalance: result['new_balance'] as int,
      bidAmount: result['bid_amount'] as int,
    );
  }
}
