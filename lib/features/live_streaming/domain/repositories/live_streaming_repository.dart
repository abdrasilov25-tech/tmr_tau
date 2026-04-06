import '../entities/live_room_entity.dart';

abstract class LiveStreamingRepository {
  Future<LiveRoomEntity> createLiveRoom({String title});

  Future<void> endLiveRoom(String roomId);

  Future<LiveRoomEntity?> getLiveRoom(String roomId);

  /// Активные эфиры (обновляется через Supabase Realtime, если включён для таблицы).
  Stream<List<LiveRoomEntity>> watchActiveLiveRooms();

  /// Завершённые эфиры текущего пользователя (обычные прямые, не баттл-комнаты).
  Future<List<LiveRoomEntity>> getMyEndedLiveRooms({int limit = 20});
}
