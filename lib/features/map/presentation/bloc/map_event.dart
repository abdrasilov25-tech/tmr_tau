import 'package:equatable/equatable.dart';

sealed class MapEvent extends Equatable {
  const MapEvent();

  @override
  List<Object?> get props => [];
}

final class MapLocationRequested extends MapEvent {
  const MapLocationRequested();
}

final class MapProductsRequested extends MapEvent {
  const MapProductsRequested({
    required this.latitude,
    required this.longitude,
    required this.radiusKm,
  });

  final double latitude;
  final double longitude;
  final double radiusKm;

  @override
  List<Object?> get props => [latitude, longitude, radiusKm];
}

final class MapRadiusChanged extends MapEvent {
  const MapRadiusChanged(this.radiusKm);

  final double radiusKm;

  @override
  List<Object?> get props => [radiusKm];
}
