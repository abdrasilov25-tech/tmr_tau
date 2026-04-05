import 'package:flutter/material.dart';

import '../entities/featured_seller.dart';
import '../entities/map_product.dart';
import '../entities/map_quest.dart';
import '../entities/map_zone.dart';

abstract class MapRepository {
  Future<List<MapProduct>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  });

  Future<int> purchaseMapBoost({
    required String productId,
    required int boostLevel,
    required int durationHours,
  });

  Future<FeaturedSeller?> getTodayFeatured();

  Future<({int newBalance, int bidAmount})> placeFeaturedBid(int bidAmount);

  Future<MapQuestProgress> getTodayQuestProgress();

  Future<({int qarmetAwarded, int newBalance, bool alreadyDone})> completeMapQuest(
    MapQuestId questId,
  );

  Future<List<MapZone>> getActiveZones();

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
}
