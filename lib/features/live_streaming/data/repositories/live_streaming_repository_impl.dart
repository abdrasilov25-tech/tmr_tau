import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/live_room_entity.dart';
import '../../domain/repositories/live_streaming_repository.dart';

class LiveStreamingRepositoryImpl implements LiveStreamingRepository {
  LiveStreamingRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<LiveRoomEntity> createLiveRoom({String title = ''}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('auth_required');
    }
    final row = await _client
        .from(SupabaseConstants.liveRoomsTable)
        .insert(<String, dynamic>{
          'host_id': uid,
          'title': title.trim(),
          'is_live': true,
        })
        .select()
        .single();
    return _map(Map<String, dynamic>.from(row as Map));
  }

  @override
  Future<void> endLiveRoom(String roomId) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    await _client
        .from(SupabaseConstants.liveRoomsTable)
        .update(<String, dynamic>{
          'is_live': false,
          'ended_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', roomId)
        .eq('host_id', uid);
  }

  @override
  Future<LiveRoomEntity?> getLiveRoom(String roomId) async {
    final row = await _client
        .from(SupabaseConstants.liveRoomsTable)
        .select()
        .eq('id', roomId)
        .maybeSingle();
    if (row == null) return null;
    return _map(Map<String, dynamic>.from(row as Map));
  }

  @override
  Stream<List<LiveRoomEntity>> watchActiveLiveRooms() {
    return _client
        .from(SupabaseConstants.liveRoomsTable)
        .stream(primaryKey: ['id'])
        .map((rows) {
          final list = <LiveRoomEntity>[];
          for (final raw in rows) {
            final row = Map<String, dynamic>.from(raw);
            if (row['is_live'] != true) continue;
            list.add(_map(row));
          }
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  LiveRoomEntity _map(Map<String, dynamic> row) {
    return LiveRoomEntity(
      id: (row['id'] ?? '').toString(),
      hostId: (row['host_id'] ?? '').toString(),
      title: (row['title'] ?? '').toString(),
      isLive: row['is_live'] == true,
      createdAt: DateTime.tryParse((row['created_at'] ?? '').toString()) ??
          DateTime.now().toUtc(),
      endedAt: DateTime.tryParse((row['ended_at'] ?? '').toString()),
    );
  }
}
