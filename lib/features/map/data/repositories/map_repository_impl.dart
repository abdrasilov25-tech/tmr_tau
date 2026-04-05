import 'package:flutter/material.dart';

import '../../domain/entities/featured_seller.dart';
import '../../domain/entities/map_product.dart';
import '../../domain/entities/map_quest.dart';
import '../../domain/entities/map_zone.dart';
import '../../domain/repositories/map_repository.dart';
import '../datasources/map_remote_datasource.dart';

class MapRepositoryImpl implements MapRepository {
  MapRepositoryImpl(this._dataSource);
  final MapRemoteDataSource _dataSource;

  @override
  Future<List<MapProduct>> getNearbyProducts({
    required double latitude,
    required double longitude,
    required double radiusKm,
  }) =>
      _dataSource.getNearbyProducts(
        latitude: latitude,
        longitude: longitude,
        radiusKm: radiusKm,
      );

  @override
  Future<int> purchaseMapBoost({
    required String productId,
    required int boostLevel,
    required int durationHours,
  }) =>
      _dataSource.purchaseMapBoost(
        productId: productId,
        boostLevel: boostLevel,
        durationHours: durationHours,
      );

  @override
  Future<FeaturedSeller?> getTodayFeatured() => _dataSource.getTodayFeatured();

  @override
  Future<({int newBalance, int bidAmount})> placeFeaturedBid(int bidAmount) =>
      _dataSource.placeFeaturedBid(bidAmount);

  @override
  Future<MapQuestProgress> getTodayQuestProgress() =>
      _dataSource.getTodayQuestProgress();

  @override
  Future<({int qarmetAwarded, int newBalance, bool alreadyDone})> completeMapQuest(
    MapQuestId questId,
  ) =>
      _dataSource.completeMapQuest(questId);

  @override
  Future<List<MapZone>> getActiveZones() => _dataSource.getActiveZones();

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
  }) =>
      _dataSource.purchaseMapZone(
        name: name,
        description: description,
        offerText: offerText,
        brandColor: brandColor,
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusMeters,
        durationDays: durationDays,
      );
}
