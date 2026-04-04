class LiveRoomEntity {
  const LiveRoomEntity({
    required this.id,
    required this.hostId,
    required this.title,
    required this.isLive,
    required this.createdAt,
    this.endedAt,
  });

  final String id;
  final String hostId;
  final String title;
  final bool isLive;
  final DateTime createdAt;
  final DateTime? endedAt;

  /// Идентификатор канала Agora (совпадает с id комнаты).
  String get agoraChannelId => id;
}
