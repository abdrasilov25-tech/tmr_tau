import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/map_product.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../widgets/map_product_sheet.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const MethodChannel _mapsConfigChannel =
      MethodChannel('tmr_tau/maps_config');
  GoogleMapController? _mapController;
  double _radiusKm = 10;
  bool _mapsConfigured = true;
  bool _accessLoading = true;
  bool _hasOfficialPageAccess = false;

  static const _radii = [5.0, 10.0, 25.0, 50.0];

  @override
  void initState() {
    super.initState();
    _checkMapsConfig();
    _checkOfficialPageAccess();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Set<Marker> _buildMarkers(List<MapProduct> products) {
    return products.where((p) {
      final latOk = p.latitude >= -90 && p.latitude <= 90;
      final lngOk = p.longitude >= -180 && p.longitude <= 180;
      return latOk && lngOk;
    }).map((p) {
      return Marker(
        markerId: MarkerId(p.id),
        position: LatLng(p.latitude, p.longitude),
        infoWindow: InfoWindow(title: p.title, snippet: p.priceFormatted),
        onTap: () => _showProductSheet(p),
      );
    }).toSet();
  }

  void _showProductSheet(MapProduct product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapProductSheet(product: product),
    );
  }

  void _onRadiusChanged(double value) {
    setState(() => _radiusKm = value);
    context.read<MapBloc>().add(MapRadiusChanged(value));
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  Future<void> _checkMapsConfig() async {
    try {
      final configured = await _mapsConfigChannel.invokeMethod<bool>(
        'isConfigured',
      );
      if (!mounted) return;
      setState(() => _mapsConfigured = configured ?? false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _mapsConfigured = false);
    }
  }

  Future<void> _checkOfficialPageAccess() async {
    setState(() => _accessLoading = true);
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser == null) {
        if (!mounted) return;
        setState(() {
          _hasOfficialPageAccess = false;
          _accessLoading = false;
        });
        return;
      }

      final row = await Supabase.instance.client
          .from('users')
          .select('official_page_active')
          .eq('id', authUser.id)
          .maybeSingle();
      if (!mounted) return;
      final hasAccess = row?['official_page_active'] == true;
      setState(() {
        _hasOfficialPageAccess = hasAccess;
        _accessLoading = false;
      });
      if (hasAccess) {
        context.read<MapBloc>().add(const MapLocationRequested());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasOfficialPageAccess = false;
        _accessLoading = false;
      });
    }
  }

  Future<void> _goToMyLocation(LatLng? position) async {
    if (position == null) {
      context.read<MapBloc>().add(const MapLocationRequested());
      return;
    }
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(position, _zoomForRadius(_radiusKm)),
    );
  }

  double _zoomForRadius(double radiusKm) {
    // Approximate: zoom 14 ≈ 1 km, each +1 zoom halves the range
    if (radiusKm <= 5) return 13;
    if (radiusKm <= 10) return 12;
    if (radiusKm <= 25) return 11;
    return 10;
  }

  @override
  Widget build(BuildContext context) {
    if (_accessLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasOfficialPageAccess) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.workspace_premium_outlined,
                      size: 52,
                      color: Color(0xFF2563EB),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Карта доступна по подписке Official Page',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Чтобы пользоваться картой и поиском рядом, '
                      'подключите подписку в Qarmet Wallet.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => context.push('/qarmet-wallet'),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Подключить Official Page'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _checkOfficialPageAccess,
                      child: const Text('Я уже оплатил, проверить снова'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: BlocConsumer<MapBloc, MapState>(
        listener: (context, state) {
          // initialCameraPosition используется только при первом создании карты;
          // без animateCamera при MapLoading камера остаётся на дефолте (часто «как Америка» в эмуляторе).
          if (state is MapLoading || state is MapLoaded) {
            final pos =
                state is MapLoaded ? state.position : (state as MapLoading).position;
            final radiusKm =
                state is MapLoaded ? state.radiusKm : (state as MapLoading).radiusKm;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _mapController?.animateCamera(
                CameraUpdate.newLatLngZoom(
                  pos,
                  _zoomForRadius(radiusKm),
                ),
              );
            });
          }
        },
        builder: (context, state) {
          final position = switch (state) {
            MapLoading(position: final p) => p,
            MapLoaded(position: final p) => p,
            _ => null,
          };
          final hasValidPosition = position != null;

          final products = state is MapLoaded ? state.products : <MapProduct>[];

          if (!_mapsConfigured) {
            return Center(
              child: Card(
                margin: const EdgeInsets.all(24),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text(
                        'Карта не настроена: отсутствует Google Maps API key',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Добавьте MAPS_API_KEY в android/local.properties и iOS xcconfig.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _checkMapsConfig,
                        child: const Text('Проверить снова'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Stack(
            children: [
              GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: position ?? const LatLng(51.1694, 71.4491), // Астана
                  zoom: _zoomForRadius(_radiusKm),
                ),
                markers: _buildMarkers(products),
                // Avoid plugin crashes when location permission/service isn't ready yet.
                myLocationEnabled: hasValidPosition,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),

              // Top bar
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on,
                                  size: 18, color: Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              Text(
                                'Рядом со мной',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (state is MapLoaded)
                                Text(
                                  '${state.products.length} объявлений',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey.shade500),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Loading / error overlay
              if (state is MapLocating || state is MapLoading)
                const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Загрузка...'),
                        ],
                      ),
                    ),
                  ),
                ),

              if (state is MapError)
                Center(
                  child: Card(
                    margin: const EdgeInsets.all(24),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.location_off,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 12),
                          Text(state.message,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => context
                                .read<MapBloc>()
                                .add(const MapLocationRequested()),
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Bottom radius selector
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 12,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Радиус поиска: ${_radiusKm.toInt()} км',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: _radii.map((r) {
                              final selected = _radiusKm == r;
                              return GestureDetector(
                                onTap: () => _onRadiusChanged(r),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF1A1A1A)
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${r.toInt()} км',
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.grey.shade700,
                                      fontWeight: selected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // My location FAB
              Positioned(
                right: 16,
                bottom: 130,
                child: FloatingActionButton.small(
                  heroTag: 'map_location',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1A1A1A),
                  onPressed: () => _goToMyLocation(position),
                  child: const Icon(Icons.my_location),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
