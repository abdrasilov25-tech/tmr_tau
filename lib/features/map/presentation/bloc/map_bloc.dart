import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../domain/usecases/get_nearby_products.dart';
import 'map_event.dart';
import 'map_state.dart';

class MapBloc extends Bloc<MapEvent, MapState> {
  MapBloc(this._getNearbyProducts) : super(const MapInitial()) {
    on<MapLocationRequested>(_onLocationRequested);
    on<MapProductsRequested>(_onProductsRequested);
    on<MapRadiusChanged>(_onRadiusChanged);
  }

  final GetNearbyProducts _getNearbyProducts;
  LatLng? _lastPosition;
  double _lastRadius = 10;

  void _safeEmit(Emitter<MapState> emit, MapState state) {
    if (!isClosed) emit(state);
  }

  void _safeAdd(MapEvent event) {
    if (!isClosed) add(event);
  }

  Future<void> _onLocationRequested(
    MapLocationRequested event,
    Emitter<MapState> emit,
  ) async {
    _safeEmit(emit, const MapLocating());
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _safeEmit(emit, const MapError(
          'Геолокация выключена. Включите её в настройках устройства.',
        ));
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _safeEmit(emit, const MapError('Доступ к геолокации запрещён в настройках'));
        return;
      }
      if (permission == LocationPermission.denied) {
        _safeEmit(emit, const MapError('Разрешите доступ к геолокации для раздела «Рядом»'));
        return;
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 25),
          ),
        );
      } catch (e) {
        pos = null;
      }

      pos ??= await Geolocator.getLastKnownPosition();
      if (pos == null) {
        _safeEmit(emit, const MapError('Не удалось определить местоположение'));
        return;
      }

      _safeAdd(MapProductsRequested(
        latitude: pos.latitude,
        longitude: pos.longitude,
        radiusKm: _lastRadius,
      ));
    } catch (e) {
      _safeEmit(emit, const MapError('Не удалось определить местоположение'));
    }
  }

  Future<void> _onProductsRequested(
    MapProductsRequested event,
    Emitter<MapState> emit,
  ) async {
    final pos = LatLng(event.latitude, event.longitude);
    _lastPosition = pos;
    _lastRadius = event.radiusKm;
    _safeEmit(emit, MapLoading(position: pos, radiusKm: event.radiusKm));
    try {
      final products = await _getNearbyProducts(
        latitude: event.latitude,
        longitude: event.longitude,
        radiusKm: event.radiusKm,
      );
      _safeEmit(
        emit,
        MapLoaded(products: products, position: pos, radiusKm: event.radiusKm),
      );
    } catch (e) {
      _safeEmit(emit, MapError(e.toString()));
    }
  }

  void _onRadiusChanged(MapRadiusChanged event, Emitter<MapState> emit) {
    final pos = _lastPosition;
    if (pos == null) return;
    _safeAdd(MapProductsRequested(
      latitude: pos.latitude,
      longitude: pos.longitude,
      radiusKm: event.radiusKm,
    ));
  }
}
