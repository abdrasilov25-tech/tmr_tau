import 'package:equatable/equatable.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../domain/entities/map_product.dart';

sealed class MapState extends Equatable {
  const MapState();

  @override
  List<Object?> get props => [];
}

final class MapInitial extends MapState {
  const MapInitial();
}

final class MapLocating extends MapState {
  const MapLocating();
}

final class MapLoading extends MapState {
  const MapLoading({required this.position, required this.radiusKm});

  final LatLng position;
  final double radiusKm;

  @override
  List<Object?> get props => [position, radiusKm];
}

final class MapLoaded extends MapState {
  const MapLoaded({
    required this.products,
    required this.position,
    required this.radiusKm,
  });

  final List<MapProduct> products;
  final LatLng position;
  final double radiusKm;

  @override
  List<Object?> get props => [products, position, radiusKm];
}

final class MapError extends MapState {
  const MapError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}
