import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class MapZone extends Equatable {
  const MapZone({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.brandColor,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.activeUntil,
    this.description,
    this.offerText,
    this.ownerAvatarUrl,
  });

  final String id;
  final String ownerId;
  final String name;
  final Color brandColor;
  final double latitude;
  final double longitude;
  final int radiusMeters;
  final DateTime activeUntil;
  final String? description;
  final String? offerText;
  final String? ownerAvatarUrl;

  bool get isActive => activeUntil.isAfter(DateTime.now().toUtc());

  /// Returns true if [lat]/[lng] is within this zone.
  bool containsPoint(double lat, double lng) {
    const earthRadius = 6371000.0; // metres
    final dLat = _toRad(lat - latitude);
    final dLng = _toRad(lng - longitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(latitude)) *
            math.cos(_toRad(lat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c <= radiusMeters;
  }

  double _toRad(double deg) => deg * math.pi / 180;

  @override
  List<Object?> get props => [id, latitude, longitude, radiusMeters, activeUntil];
}
