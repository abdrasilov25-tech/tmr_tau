import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../product/data/services/payment_service.dart';
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
  bool _shareMyLocation = false;
  bool _friendsLoading = false;
  bool _businessActionLoading = false;
  List<_FriendLocation> _friends = const <_FriendLocation>[];
  LatLng? _myPosition;
  // Временный предпросмотр карты без подписки (для демонстрации дизайна).
  // После проверки установите false.
  static const bool _temporaryPreviewUnlock = false;

  static const _radii = [5.0, 10.0, 25.0, 50.0];

  @override
  void initState() {
    super.initState();
    _checkMapsConfig();
    _checkOfficialPageAccess();
    _loadShareLocationStatus();
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
        icon: p.isTop
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange)
            : (p.isUrgent
                ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose)
                : BitmapDescriptor.defaultMarker),
        infoWindow: InfoWindow(title: p.title, snippet: p.priceFormatted),
        onTap: () => _showProductSheet(p),
      );
    }).toSet();
  }

  Set<Marker> _buildFriendMarkers() {
    return _friends.map((f) {
      return Marker(
        markerId: MarkerId('friend_${f.id}'),
        position: LatLng(f.latitude, f.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: f.name, snippet: 'Друг на карте'),
        onTap: () => _showFriendSheet(f),
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

  Future<void> _loadShareLocationStatus() async {
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      if (authUser == null) return;
      final row = await Supabase.instance.client
          .from('users')
          .select('share_location')
          .eq('id', authUser.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() => _shareMyLocation = row?['share_location'] == true);
    } catch (_) {}
  }

  Future<void> _setShareLocation(bool enabled) async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;
    await Supabase.instance.client.from('users').update({
      'share_location': enabled,
      if (!enabled) 'live_latitude': null,
      if (!enabled) 'live_longitude': null,
      'live_location_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', authUser.id);
    if (!mounted) return;
    setState(() => _shareMyLocation = enabled);
    if (enabled && _myPosition != null) {
      await _syncMyLiveLocation(_myPosition!);
    }
    await _loadFriendsLocations();
  }

  Future<void> _syncMyLiveLocation(LatLng pos) async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null || !_shareMyLocation) return;
    await Supabase.instance.client.from('users').update({
      'live_latitude': pos.latitude,
      'live_longitude': pos.longitude,
      'live_location_updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', authUser.id);
  }

  Future<void> _loadFriendsLocations() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;
    setState(() => _friendsLoading = true);
    try {
      final followingRes = await Supabase.instance.client
          .from('followers')
          .select('following_id')
          .eq('follower_id', authUser.id);
      final followersRes = await Supabase.instance.client
          .from('followers')
          .select('follower_id')
          .eq('following_id', authUser.id);
      final followingIds = (followingRes as List)
          .map((e) => (e as Map<String, dynamic>)['following_id'] as String?)
          .whereType<String>()
          .toSet();
      final followerIds = (followersRes as List)
          .map((e) => (e as Map<String, dynamic>)['follower_id'] as String?)
          .whereType<String>()
          .toSet();
      final friendIds = followingIds.intersection(followerIds).toList(growable: false);
      if (friendIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _friends = const <_FriendLocation>[];
          _friendsLoading = false;
        });
        return;
      }
      final users = await Supabase.instance.client
          .from('users')
          .select('id,name,avatar,share_location,live_latitude,live_longitude')
          .inFilter('id', friendIds)
          .eq('share_location', true)
          .not('live_latitude', 'is', null)
          .not('live_longitude', 'is', null);
      final mapped = (users as List).map((e) {
        final m = e as Map<String, dynamic>;
        return _FriendLocation(
          id: m['id'] as String,
          name: (m['name'] as String?) ?? 'Друг',
          avatarUrl: m['avatar'] as String?,
          latitude: (m['live_latitude'] as num).toDouble(),
          longitude: (m['live_longitude'] as num).toDouble(),
        );
      }).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _friends = mapped;
        _friendsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _friendsLoading = false);
    }
  }

  Future<void> _sendSticker(String friendId, String sticker) async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;
    await Supabase.instance.client.from('messages').insert({
      'sender_id': authUser.id,
      'receiver_id': friendId,
      'text': sticker,
    });
  }

  Future<void> _openRouteToFriend(_FriendLocation friend) async {
    final from = _myPosition;
    final destination = '${friend.latitude},${friend.longitude}';
    final url = from == null
        ? 'https://www.google.com/maps/dir/?api=1&destination=$destination'
        : 'https://www.google.com/maps/dir/?api=1&origin=${from.latitude},${from.longitude}&destination=$destination&travelmode=driving';
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showFriendSheet(_FriendLocation friend) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(friend.name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      context.push('/chat/${friend.id}?name=${Uri.encodeComponent(friend.name)}');
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Написать'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _sendSticker(friend.id, '🫶');
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Стикер отправлен')),
                      );
                    },
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    label: const Text('Стикер'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await _openRouteToFriend(friend);
                    },
                    icon: const Icon(Icons.alt_route_rounded),
                    label: const Text('Маршрут'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
      final hasAccess =
          (row?['official_page_active'] == true) || _temporaryPreviewUnlock;
      setState(() {
        _hasOfficialPageAccess = hasAccess;
        _accessLoading = false;
      });
      if (hasAccess) {
        context.read<MapBloc>().add(const MapLocationRequested());
        await _loadFriendsLocations();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasOfficialPageAccess = false;
        _accessLoading = false;
      });
    }
  }

  Future<void> _buyBusinessSubscriptionQuick() async {
    if (_businessActionLoading) return;
    final payment = context.read<PaymentService>();
    setState(() => _businessActionLoading = true);
    try {
      final result = await payment.buyQarmetPackage(PaymentService.officialPageProductId);
      if (!mounted) return;
      if (result.status == PaymentResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Бизнес-подписка активирована')),
        );
        await _checkOfficialPageAccess();
      } else if (result.status == PaymentResultStatus.cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Покупка отменена')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message ?? 'Не удалось выполнить покупку')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка покупки, попробуйте позже')),
      );
    } finally {
      if (mounted) {
        setState(() => _businessActionLoading = false);
      }
    }
  }

  Widget _buildBusinessMonetizationPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.storefront_rounded, color: Color(0xFF16A34A), size: 18),
              const SizedBox(width: 8),
              Text(
                'Для локального бизнеса',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                'деньги 💰',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.green.shade700, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Закрепи точку, публикуй акции и продвигайся в 1-2 тапа.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/add-product'),
                icon: const Icon(Icons.place_outlined),
                label: const Text('Закрепить точку'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/nearby'),
                icon: const Icon(Icons.local_offer_outlined),
                label: const Text('Публиковать акции'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/qarmet-wallet'),
                icon: const Icon(Icons.trending_up_rounded),
                label: const Text('Продвигать'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _businessActionLoading ? null : _buyBusinessSubscriptionQuick,
              icon: _businessActionLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.workspace_premium_outlined),
              label: const Text('Подключить бизнес за 1 тап'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBusinessPoints(List<MapProduct> products) {
    final promoted = products.where((p) => p.isTop || p.isUrgent).take(5).toList();
    if (promoted.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department, color: Color(0xFFF97316), size: 18),
              const SizedBox(width: 8),
              Text(
                'ТОП бизнес точки',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in promoted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _showProductSheet(p),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (p.isTop)
                      _smallPill('TOP', const Color(0xFFF97316))
                    else if (p.isUrgent)
                      _smallPill('АКЦИЯ', const Color(0xFFE11D48)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMiniPriceEstimator() {
    const startPrice = 199.0;
    const startQarmet = 3.0;
    const premiumPrice = 499.0;
    const premiumQarmet = 12.0;
    const businessPrice = 1299.0;
    const businessQarmet = 55.0;
    final startPerQarmet = startPrice / startQarmet;
    final premiumPerQarmet = premiumPrice / premiumQarmet;
    final businessPerQarmet = businessPrice / businessQarmet;
    final bestPerQarmet = businessPerQarmet;

    String fmt(double value) => value.toStringAsFixed(0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Мини-прайс в тенге',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '1 Qarmet: Start ~${fmt(startPerQarmet)} ₸, Premium ~${fmt(premiumPerQarmet)} ₸, '
            'Business ~${fmt(businessPerQarmet)} ₸',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Ориентир (выгодный пакет):',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'TOP +24ч (1 Qarmet) ~ ${fmt(bestPerQarmet)} ₸',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Срочно +24ч (1 Qarmet) ~ ${fmt(bestPerQarmet)} ₸',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Выделение +24ч (1 Qarmet) ~ ${fmt(bestPerQarmet)} ₸',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Все и сразу +24ч (2 Qarmet) ~ ${fmt(bestPerQarmet * 2)} ₸',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  void _showFriendsControlsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Друзья на карте',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Показывать меня друзьям')),
                  Switch(
                    value: _shareMyLocation,
                    onChanged: (v) => _setShareLocation(v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _loadFriendsLocations,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Обновить'),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Виден друзей: ${_friends.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBusinessControlsSheet(List<MapProduct> products) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              _buildBusinessMonetizationPanel(),
              const SizedBox(height: 10),
              _buildMiniPriceEstimator(),
              const SizedBox(height: 10),
              _buildTopBusinessPoints(products),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smallPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
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
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Шаг 1: Подключи Official Page'),
                          SizedBox(height: 4),
                          Text('Шаг 2: Закрепляй точку и запускай акции'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _businessActionLoading ? null : _buyBusinessSubscriptionQuick,
                        icon: _businessActionLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.flash_on_rounded),
                        label: const Text('Подключить за 1 тап'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/qarmet-wallet'),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Подробнее по тарифам'),
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
            _myPosition = pos;
            unawaited(_syncMyLiveLocation(pos));
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
                markers: {..._buildMarkers(products), ..._buildFriendMarkers()},
                // Avoid plugin crashes when location permission/service isn't ready yet.
                myLocationEnabled: hasValidPosition,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),

              // Top bar
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    children: [
                      Row(
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
                      if (_temporaryPreviewUnlock) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: const Text(
                            'Временный режим предпросмотра: карта открыта без подписки.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _showFriendsControlsSheet,
                                icon: const Icon(Icons.group_outlined),
                                label: Text(
                                  _friendsLoading
                                      ? 'Друзья...'
                                      : 'Друзья (${_friends.length})',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _showBusinessControlsSheet(products),
                                icon: const Icon(Icons.storefront_outlined),
                                label: const Text('Бизнес'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _smallPill('Друг', const Color(0xFF2563EB)),
                            _smallPill('TOP', const Color(0xFFF97316)),
                            _smallPill('АКЦИЯ', const Color(0xFFE11D48)),
                          ],
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
              Positioned(
                right: 16,
                bottom: 184,
                child: FloatingActionButton.small(
                  heroTag: 'map_friends_refresh',
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2563EB),
                  onPressed: _loadFriendsLocations,
                  child: const Icon(Icons.group_outlined),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FriendLocation {
  const _FriendLocation({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String name;
  final String? avatarUrl;
  final double latitude;
  final double longitude;
}
