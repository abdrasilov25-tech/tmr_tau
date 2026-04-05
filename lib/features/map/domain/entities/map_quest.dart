import 'package:equatable/equatable.dart';

enum MapQuestId {
  openMap,
  view3Listings,
  messageSeller,
  placeAuctionBid,
  shareLocationFriend;

  String get rpcId => switch (this) {
        openMap => 'open_map',
        view3Listings => 'view_3_listings',
        messageSeller => 'message_seller',
        placeAuctionBid => 'place_auction_bid',
        shareLocationFriend => 'share_location_friend',
      };
}

class MapQuestDefinition {
  const MapQuestDefinition({
    required this.id,
    required this.title,
    required this.description,
    required this.reward,
    this.requiresQuestPass = false,
  });

  final MapQuestId id;
  final String title;
  final String description;
  final int reward;
  final bool requiresQuestPass;

  static const all = [
    MapQuestDefinition(
      id: MapQuestId.openMap,
      title: 'Открой карту',
      description: 'Просто зайди в раздел карты сегодня',
      reward: 5,
    ),
    MapQuestDefinition(
      id: MapQuestId.view3Listings,
      title: 'Посмотри 3 объявления',
      description: 'Открой карточки 3 продавцов на карте',
      reward: 10,
    ),
    MapQuestDefinition(
      id: MapQuestId.messageSeller,
      title: 'Напиши продавцу',
      description: 'Отправь сообщение продавцу с карты',
      reward: 20,
    ),
    MapQuestDefinition(
      id: MapQuestId.placeAuctionBid,
      title: 'Сделай ставку в аукционе',
      description: 'Поучаствуй в аукционе "Продавец дня"',
      reward: 30,
      requiresQuestPass: true,
    ),
    MapQuestDefinition(
      id: MapQuestId.shareLocationFriend,
      title: 'Поделись локацией',
      description: 'Включи видимость для друзей на карте',
      reward: 25,
      requiresQuestPass: true,
    ),
  ];

  static int get freeQarmetMax =>
      all.where((q) => !q.requiresQuestPass).fold(0, (s, q) => s + q.reward);

  static int get totalQarmetMax =>
      all.fold(0, (s, q) => s + q.reward);
}

class MapQuestProgress extends Equatable {
  const MapQuestProgress({
    required this.completedIds,
    required this.totalEarnedToday,
    required this.hasQuestPass,
  });

  final Set<String> completedIds;
  final int totalEarnedToday;
  final bool hasQuestPass;

  bool isCompleted(MapQuestId id) => completedIds.contains(id.rpcId);

  int get completedCount => completedIds.length;

  int get freeCompletedCount => MapQuestDefinition.all
      .where((q) => !q.requiresQuestPass && completedIds.contains(q.id.rpcId))
      .length;

  int get freeTotal => MapQuestDefinition.all.where((q) => !q.requiresQuestPass).length;

  @override
  List<Object?> get props => [completedIds, totalEarnedToday, hasQuestPass];
}
