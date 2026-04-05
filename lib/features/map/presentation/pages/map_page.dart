import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../product/data/services/payment_service.dart';
import '../../data/datasources/map_remote_datasource.dart';
import '../../domain/entities/featured_seller.dart';
import '../../domain/entities/map_product.dart';
import '../../domain/entities/map_quest.dart';
import '../../domain/entities/map_zone.dart';
import '../../domain/entities/mystery_spot.dart';
import '../bloc/map_bloc.dart';
import '../bloc/map_event.dart';
import '../bloc/map_state.dart';
import '../widgets/featured_bid_sheet.dart';
import '../widgets/featured_seller_banner.dart';
import '../widgets/map_product_sheet.dart';
import '../widgets/map_quest_sheet.dart';
import '../widgets/map_leaderboard_sheet.dart';
import '../widgets/mystery_spot_sheet.dart';
import '../widgets/zone_banner.dart';
import '../widgets/zone_purchase_sheet.dart';

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  static const MethodChannel _mapsConfigChannel =
      MethodChannel('tmr_tau/maps_config');
  GoogleMapController? _mapController;
  late final MapRemoteDataSource _mapDataSource =
      MapRemoteDataSourceImpl(Supabase.instance.client);
  double _radiusKm = 10;
  FeaturedSeller? _featuredSeller;
  bool _featuredLoading = false;
  int? _myFeaturedBid;
  MapQuestProgress _questProgress = const MapQuestProgress(
    completedIds: {},
    totalEarnedToday: 0,
    hasQuestPass: false,
  );
  int _listingsViewedToday = 0;
  List<MapZone> _activeZones = const [];
  MapZone? _currentZone;
  bool _zoneDismissed = false;
  MysterySpot? _mysterySpot;
  bool _mapsConfigured = true;
  bool _accessLoading = true;
  bool _hasOfficialPageAccess = false;
  bool _shareMyLocation = false;
  bool _friendsLoading = false;
  bool _businessActionLoading = false;
  bool _cosmeticsStickerUnlocked = false;
  bool _cosmeticsPurchaseLoading = false;
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
    _loadFeaturedSeller();
    _loadQuestProgress();
    _loadActiveZones();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCosmeticsStickerAccess();
      // Auto-complete "open map" quest
      _tryCompleteQuest(MapQuestId.openMap);
    });
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadMysterySpot(LatLng pos) async {
    try {
      final spot = await _mapDataSource.getTodayMysterySpot(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      if (!mounted) return;
      setState(() => _mysterySpot = spot);
    } catch (_) {}
  }

  Marker? _buildMysteryMarker() {
    final spot = _mysterySpot;
    if (spot == null) return null;
    final label = spot.alreadyClaimed ? '🔒' : '❓';
    return Marker(
      markerId: const MarkerId('mystery_spot'),
      position: LatLng(spot.latitude, spot.longitude),
      icon: spot.alreadyClaimed
          ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet)
          : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
      zIndexInt: 3,
      infoWindow: InfoWindow(
        title: '$label Mystery Spot',
        snippet: spot.alreadyClaimed
            ? 'Уже открыт'
            : '+${spot.qarmetReward} Qarmet — нажми чтобы открыть',
      ),
      onTap: () => _openMysterySpotSheet(spot),
    );
  }

  void _openMysterySpotSheet(MysterySpot spot) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MysterySpotRevealSheet(
        spot: spot,
        dataSource: _mapDataSource,
        onRevealed: () {
          // Mark as claimed locally
          setState(() {
            _mysterySpot = MysterySpot(
              id: spot.id,
              latitude: spot.latitude,
              longitude: spot.longitude,
              qarmetReward: spot.qarmetReward,
              alreadyClaimed: true,
              isSellerSponsored: spot.isSellerSponsored,
              sellerName: spot.sellerName,
              sellerOffer: spot.sellerOffer,
              sellerId: spot.sellerId,
              productId: spot.productId,
            );
          });
          // Also complete quest
          _tryCompleteQuest(MapQuestId.openMap);
        },
      ),
    );
  }

  Set<Circle> _buildZoneCircles() {
    return _activeZones.map((zone) {
      final isActive = _currentZone?.id == zone.id;
      return Circle(
        circleId: CircleId(zone.id),
        center: LatLng(zone.latitude, zone.longitude),
        radius: zone.radiusMeters.toDouble(),
        fillColor: zone.brandColor.withValues(alpha: isActive ? 0.18 : 0.10),
        strokeColor: zone.brandColor.withValues(alpha: isActive ? 0.7 : 0.4),
        strokeWidth: isActive ? 2 : 1,
        onTap: () => _openZoneDetail(zone),
      );
    }).toSet();
  }

  Future<void> _loadActiveZones() async {
    try {
      final zones = await _mapDataSource.getActiveZones();
      if (!mounted) return;
      setState(() => _activeZones = zones);
      if (_myPosition != null) _checkCurrentZone(_myPosition!);
    } catch (_) {}
  }

  void _checkCurrentZone(LatLng pos) {
    final zone = _activeZones.cast<MapZone?>().firstWhere(
          (z) => z!.containsPoint(pos.latitude, pos.longitude),
          orElse: () => null,
        );
    if (zone?.id != _currentZone?.id) {
      setState(() {
        _currentZone = zone;
        _zoneDismissed = false;
      });
    }
  }

  void _openLeaderboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapLeaderboardSheet(dataSource: _mapDataSource),
    );
  }

  void _openZonePurchaseSheet() {
    final pos = _myPosition;
    if (pos == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ZonePurchaseSheet(
        dataSource: _mapDataSource,
        currentLat: pos.latitude,
        currentLng: pos.longitude,
        onPurchased: _loadActiveZones,
      ),
    );
  }

  void _openZoneDetail(MapZone zone) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ZoneDetailSheet(zone: zone),
    );
  }

  Future<void> _loadQuestProgress() async {
    try {
      final progress = await _mapDataSource.getTodayQuestProgress();
      if (!mounted) return;
      setState(() => _questProgress = progress);
    } catch (_) {}
  }

  Future<void> _tryCompleteQuest(MapQuestId questId) async {
    if (_questProgress.isCompleted(questId)) return;
    try {
      final result = await _mapDataSource.completeMapQuest(questId);
      if (!mounted || result.alreadyDone || result.qarmetAwarded == 0) return;
      setState(() {
        _questProgress = MapQuestProgress(
          completedIds: {
            ..._questProgress.completedIds,
            questId.rpcId,
          },
          totalEarnedToday:
              _questProgress.totalEarnedToday + result.qarmetAwarded,
          hasQuestPass: _questProgress.hasQuestPass,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Text('⚡ ', style: TextStyle(fontSize: 16)),
              Text(
                'Квест выполнен! +${result.qarmetAwarded} Qarmet',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF16A34A),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (_) {}
  }

  void _onListingViewed() {
    if (_questProgress.isCompleted(MapQuestId.view3Listings)) return;
    _listingsViewedToday++;
    if (_listingsViewedToday >= 3) {
      _tryCompleteQuest(MapQuestId.view3Listings);
    }
  }

  void _onMessagedSeller() => _tryCompleteQuest(MapQuestId.messageSeller);

  void _onAuctionBidPlaced() => _tryCompleteQuest(MapQuestId.placeAuctionBid);

  void _onLocationShared() => _tryCompleteQuest(MapQuestId.shareLocationFriend);

  void _openQuestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapQuestSheet(
        progress: _questProgress,
        onQuestPassTap: () {
          Navigator.of(context).pop();
          context.push('/qarmet-wallet');
        },
      ),
    );
  }

  Future<void> _loadFeaturedSeller() async {
    setState(() => _featuredLoading = true);
    try {
      final featured = await _mapDataSource.getTodayFeatured();
      if (!mounted) return;
      final uid = Supabase.instance.client.auth.currentUser?.id;
      setState(() {
        _featuredSeller = featured;
        _myFeaturedBid = (uid != null && featured?.userId == uid) ? featured?.bidAmount : null;
        _featuredLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _featuredLoading = false);
    }
  }

  void _openFeaturedBidSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FeaturedBidSheet(
          dataSource: _mapDataSource,
          currentFeatured: _featuredSeller,
          myCurrentBid: _myFeaturedBid,
          onBidPlaced: (newBalance) {
            _loadFeaturedSeller();
            _onAuctionBidPlaced();
          },
        ),
      ),
    );
  }

  void _openFeaturedSellerProfile() {
    final featured = _featuredSeller;
    if (featured == null) return;
    context.push('/profile/${featured.userId}');
  }

  Set<Marker> _buildMarkers(List<MapProduct> products) {
    // Sort so boosted markers render on top (set preserves insertion order for GoogleMaps z-index).
    final sorted = [...products]..sort((a, b) => b.mapBoostLevel.index.compareTo(a.mapBoostLevel.index));

    return sorted.where((p) {
      final latOk = p.latitude >= -90 && p.latitude <= 90;
      final lngOk = p.longitude >= -180 && p.longitude <= 180;
      return latOk && lngOk;
    }).map((p) {
      final BitmapDescriptor icon;
      if (p.isBoosted && p.mapBoostLevel == MapBoostLevel.topZone) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      } else if (p.isBoosted && p.mapBoostLevel == MapBoostLevel.boost) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan);
      } else if (p.isTop) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      } else if (p.isUrgent) {
        icon = BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRose);
      } else {
        icon = BitmapDescriptor.defaultMarker;
      }

      final stickerPrefix =
          p.mapMarkerSticker != null ? '${p.mapMarkerSticker} ' : '';
      final boostSuffix = p.isBoosted
          ? (p.mapBoostLevel == MapBoostLevel.topZone ? ' ⭐' : ' 🚀')
          : '';

      return Marker(
        markerId: MarkerId(p.id),
        position: LatLng(p.latitude, p.longitude),
        icon: icon,
        zIndexInt: p.mapBoostLevel == MapBoostLevel.topZone
            ? 2
            : p.mapBoostLevel == MapBoostLevel.boost
                ? 1
                : 0,
        infoWindow: InfoWindow(
          title: '$stickerPrefix${p.title}$boostSuffix',
          snippet: p.priceFormatted,
        ),
        onTap: () {
          if (!_ensureOfficialPageAccess()) return;
          _showProductSheet(p);
        },
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
        onTap: () {
          if (!_ensureOfficialPageAccess()) return;
          _showFriendSheet(f);
        },
      );
    }).toSet();
  }

  void _showProductSheet(MapProduct product) {
    _onListingViewed();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MapProductSheet(
        product: product,
        dataSource: _mapDataSource,
        onBoostPurchased: () => context.read<MapBloc>().add(MapRadiusChanged(_radiusKm)),
        onMessagedSeller: _onMessagedSeller,
      ),
    );
  }

  void _onRadiusChanged(double value) {
    if (!_ensureOfficialPageAccess()) return;
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
      _onLocationShared();
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

  Future<void> _loadCosmeticsStickerAccess() async {
    if (!mounted) return;
    final payment = context.read<PaymentService>();
    final ok = await payment.getCosmeticsLifetimeUnlocked();
    if (mounted) setState(() => _cosmeticsStickerUnlocked = ok);
  }

  Future<void> _purchaseCosmeticsForStickers() async {
    if (_cosmeticsPurchaseLoading) return;
    final payment = context.read<PaymentService>();
    setState(() => _cosmeticsPurchaseLoading = true);
    try {
      final result = await payment.purchaseProfileCosmeticsLifetime();
      if (!mounted) return;
      if (result.status == PaymentResultStatus.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Оформление активировано — можно отправлять стикеры с карты',
            ),
          ),
        );
        await _loadCosmeticsStickerAccess();
      } else if (result.status == PaymentResultStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Не удалось оформить покупку'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cosmeticsPurchaseLoading = false);
    }
  }

  Future<void> _showCosmeticsRequiredForStickers() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Стикеры с карты'),
        content: const Text(
          'Отправка стикеров друзьям с карты доступна с покупкой '
          '«Оформление навсегда»: галочка, рамка и значок в профиле '
          'без траты Qarmet.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: _cosmeticsPurchaseLoading
                ? null
                : () async {
                    Navigator.pop(ctx);
                    await _purchaseCosmeticsForStickers();
                  },
            child: const Text('Купить'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendStickerToFriend(String friendId, String sticker) async {
    final payment = context.read<PaymentService>();
    final unlocked = await payment.getCosmeticsLifetimeUnlocked();
    if (mounted) setState(() => _cosmeticsStickerUnlocked = unlocked);
    if (!unlocked) {
      if (!mounted) return;
      await _showCosmeticsRequiredForStickers();
      return;
    }
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;
    await Supabase.instance.client.from('messages').insert({
      'sender_id': authUser.id,
      'receiver_id': friendId,
      'text': sticker,
    });
  }

  Future<void> _sendSticker(String friendId, String sticker) async {
    await _sendStickerToFriend(friendId, sticker);
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

  Future<void> _showFriendSheet(_FriendLocation friend) async {
    await _loadCosmeticsStickerAccess();
    if (!mounted) return;
    await showModalBottomSheet<void>(
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
                      if (!mounted) return;
                      if (_cosmeticsStickerUnlocked) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Стикер отправлен')),
                        );
                      }
                    },
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    label: Text(
                      _cosmeticsStickerUnlocked
                          ? 'Стикер'
                          : 'Стикер (оформление)',
                    ),
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
        if (mounted) {
          context.read<MapBloc>().add(const MapLocationRequested());
        }
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
        unawaited(_loadFriendsLocations());
      } else {
        // Подгружаем каталог StoreKit заранее — «Подключить за 1 тап» не ждёт холодный initStore.
        unawaited(context.read<PaymentService>().initStore());
      }
      if (mounted) {
        context.read<MapBloc>().add(const MapLocationRequested());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasOfficialPageAccess = false;
        _accessLoading = false;
      });
      if (mounted) {
        context.read<MapBloc>().add(const MapLocationRequested());
      }
    }
  }

  void _showOfficialPageRequiredSheet() {
    unawaited(context.read<PaymentService>().initStore());
    final mapContext = context;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _OfficialPageSubscriptionSheet(
        mapContext: mapContext,
        onPurchaseCompleted: _onOfficialPagePurchaseResult,
        onRecheckAccess: _checkOfficialPageAccess,
      ),
    );
  }

  void _onOfficialPagePurchaseResult(PaymentResult result) {
    if (!mounted) return;
    switch (result.status) {
      case PaymentResultStatus.success:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Бизнес-подписка активирована')),
        );
        unawaited(_checkOfficialPageAccess());
      case PaymentResultStatus.cancelled:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Покупка отменена')),
        );
      case PaymentResultStatus.error:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Не удалось выполнить покупку'),
          ),
        );
    }
  }

  bool _ensureOfficialPageAccess() {
    if (_hasOfficialPageAccess) return true;
    _showOfficialPageRequiredSheet();
    return false;
  }

  Future<void> _buyBusinessSubscriptionQuick() async {
    if (_businessActionLoading) return;
    setState(() => _businessActionLoading = true);
    try {
      await context.read<PaymentService>().initStore();
      if (!mounted) return;
      final result = await context
          .read<PaymentService>()
          .buyQarmetPackage(PaymentService.officialPageProductId);
      if (!mounted) return;
      _onOfficialPagePurchaseResult(result);
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
              OutlinedButton.icon(
                onPressed: _openZonePurchaseSheet,
                icon: const Icon(Icons.radar_rounded),
                label: const Text('Zone Takeover'),
              ),
              OutlinedButton.icon(
                onPressed: _openLeaderboard,
                icon: const Icon(Icons.leaderboard_rounded),
                label: const Text('Рейтинг'),
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
    if (!_ensureOfficialPageAccess()) return;
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
    if (!_ensureOfficialPageAccess()) return;
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

    return Scaffold(
      body: BlocConsumer<MapBloc, MapState>(
        listener: (context, state) {
          // initialCameraPosition используется только при первом создании карты;
          // без animateCamera при MapLoading камера остаётся на дефолте (часто «как Америка» в эмуляторе).
          if (state is MapLoading || state is MapLoaded) {
            final pos =
                state is MapLoaded ? state.position : (state as MapLoading).position;
            _myPosition = pos;
            _checkCurrentZone(pos);
            unawaited(_syncMyLiveLocation(pos));
            if (_mysterySpot == null) unawaited(_loadMysterySpot(pos));
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
                markers: {
                  ..._buildMarkers(products),
                  ..._buildFriendMarkers(),
                  if (_buildMysteryMarker() != null) _buildMysteryMarker()!,
                },
                circles: _buildZoneCircles(),
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

              // Zone banner (shown when inside an active zone)
              if (_currentZone != null && !_zoneDismissed)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 166,
                  child: ZoneBanner(
                    zone: _currentZone!,
                    onTap: () => _openZoneDetail(_currentZone!),
                    onDismiss: () => setState(() => _zoneDismissed = true),
                  ),
                ),

              // Featured Seller banner (above radius selector)
              if (!_featuredLoading)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 110,
                  child: _featuredSeller != null
                      ? FeaturedSellerBanner(
                          featured: _featuredSeller!,
                          currentUserId:
                              Supabase.instance.client.auth.currentUser?.id,
                          onBidTap: _openFeaturedBidSheet,
                          onSellerTap: _openFeaturedSellerProfile,
                        )
                      : FeaturedSellerEmptyBanner(
                          onBidTap: _openFeaturedBidSheet,
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

              // Quest FAB (left side)
              Positioned(
                left: 16,
                bottom: 130,
                child: _QuestFab(
                  progress: _questProgress,
                  onTap: _openQuestSheet,
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
                  onPressed: () {
                    if (!_ensureOfficialPageAccess()) return;
                    _loadFriendsLocations();
                  },
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

/// Compact quest progress FAB shown on the left of the map.
class _QuestFab extends StatelessWidget {
  const _QuestFab({required this.progress, required this.onTap});

  final MapQuestProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = progress.freeCompletedCount;
    final total = progress.freeTotal;
    final allFreeDone = done >= total;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: allFreeDone ? const Color(0xFF16A34A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              allFreeDown ? '✅' : '⚡',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(width: 6),
            Text(
              '$done/$total квестов',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: allFreeDown ? Colors.white : const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get allFreeDown => progress.freeCompletedCount >= progress.freeTotal;
}

class _OfficialPageSubscriptionSheet extends StatefulWidget {
  const _OfficialPageSubscriptionSheet({
    required this.mapContext,
    required this.onPurchaseCompleted,
    required this.onRecheckAccess,
  });

  final BuildContext mapContext;
  final void Function(PaymentResult result) onPurchaseCompleted;
  final Future<void> Function() onRecheckAccess;

  @override
  State<_OfficialPageSubscriptionSheet> createState() =>
      _OfficialPageSubscriptionSheetState();
}

class _OfficialPageSubscriptionSheetState
    extends State<_OfficialPageSubscriptionSheet> {
  bool _buying = false;

  Future<void> _onBuyTap() async {
    if (_buying) return;
    setState(() => _buying = true);
    try {
      await context.read<PaymentService>().initStore();
      if (!mounted) return;
      final result = await context.read<PaymentService>().buyQarmetPackage(
            PaymentService.officialPageProductId,
          );
      if (!mounted) return;
      if (result.status == PaymentResultStatus.success) {
        Navigator.of(context).pop();
      }
      widget.onPurchaseCompleted(result);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка покупки, попробуйте позже')),
      );
    } finally {
      if (mounted) {
        setState(() => _buying = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(widget.mapContext).textTheme.titleLarge;
    final bodyStyle = Theme.of(widget.mapContext).textTheme.bodyMedium;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium_outlined,
              size: 48,
              color: Color(0xFF2563EB),
            ),
            const SizedBox(height: 12),
            Text(
              'Нужна подписка Official Page',
              textAlign: TextAlign.center,
              style: titleStyle?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Карту можно смотреть бесплатно. Чтобы открывать объявления, '
              'менять радиус поиска, видеть друзей и инструменты бизнеса — '
              'подключите подписку в Qarmet Wallet.',
              textAlign: TextAlign.center,
              style: bodyStyle?.copyWith(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _buying ? null : _onBuyTap,
                icon: _buying
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
                onPressed: () {
                  Navigator.pop(context);
                  widget.mapContext.push('/qarmet-wallet');
                },
                icon: const Icon(Icons.account_balance_wallet_outlined),
                label: const Text('Подробнее по тарифам'),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                unawaited(widget.onRecheckAccess());
              },
              child: const Text('Я уже оплатил, проверить снова'),
            ),
          ],
        ),
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
