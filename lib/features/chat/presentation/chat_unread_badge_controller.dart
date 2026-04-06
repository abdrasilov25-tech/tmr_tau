import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/supabase_constants.dart';
import '../../../core/storage/chat_list_storage.dart';
import '../data/direct_incoming_unread_compute.dart';
import '../data/group_channel_unread_compute.dart';

/// Глобальный счётчик непрочитанных для бейджа «Чаты»: личные диалоги, группы и чужие каналы.
class ChatUnreadBadgeController extends ChangeNotifier {
  ChatUnreadBadgeController({required ChatListStorage chatListStorage})
      : _chatListStorage = chatListStorage;

  final ChatListStorage _chatListStorage;

  static const int _kMessagesListLimit = 500;

  int _total = 0;
  int get total => _total;

  bool _busy = false;

  /// Короткая подпись: `1`…`99` или `99+`.
  String get badgeShortLabel {
    if (_total <= 0) return '';
    if (_total > 99) return '99+';
    return '$_total';
  }

  void clear() {
    if (_total != 0) {
      _total = 0;
      notifyListeners();
    }
  }

  /// Пересчитать из БД и локальных отметок [ChatListStorage].
  Future<void> refresh() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      clear();
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      final results = await Future.wait<int>([
        _countDirectUnread(client, uid),
        _countGroupUnread(client, uid),
        _countChannelUnread(client, uid),
      ]);
      final sum = results[0] + results[1] + results[2];
      if (_total != sum) {
        _total = sum;
        notifyListeners();
      }
    } catch (e) {
      // Оставляем последнее известное значение.
    } finally {
      _busy = false;
    }
  }

  Future<int> _countDirectUnread(SupabaseClient client, String uid) async {
    final res = await client
        .from(SupabaseConstants.messagesTable)
        .select()
        .or('sender_id.eq.$uid,receiver_id.eq.$uid')
        .order('created_at', ascending: false)
        .limit(_kMessagesListLimit);

    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return 0;

    final peerIds = <String>{};
    for (final json in rows) {
      final senderId = json['sender_id'] as String;
      final receiverId = json['receiver_id'] as String;
      peerIds.add(senderId == uid ? receiverId : senderId);
    }

    final lastReadIsoByPeer = <String, String?>{};
    for (final id in peerIds) {
      lastReadIsoByPeer[id] = _chatListStorage.getLastReadAt(id)?.toIso8601String();
    }

    return computeTotalDirectUnreadAsync(
      DirectUnreadComputeArgs(
        rows: rows,
        currentUserId: uid,
        lastReadIsoByPeer: lastReadIsoByPeer,
      ),
    );
  }

  Future<int> _countGroupUnread(SupabaseClient client, String uid) async {
    final membershipRes = await client
        .from(SupabaseConstants.chatGroupMembersTable)
        .select('group_id')
        .eq('user_id', uid);
    final groupIds = (membershipRes as List)
        .map((e) => (e as Map<String, dynamic>)['group_id'] as String?)
        .whereType<String>()
        .toList();
    if (groupIds.isEmpty) return 0;

    final res = await client
        .from(SupabaseConstants.chatGroupMessagesTable)
        .select('group_id,sender_id,created_at,kind')
        .inFilter('group_id', groupIds)
        .order('created_at', ascending: false)
        .limit(_kMessagesListLimit);

    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return 0;

    final lastReadIsoByGroupId = <String, String?>{};
    for (final id in groupIds) {
      lastReadIsoByGroupId[id] =
          _chatListStorage.getLastReadAt(id)?.toIso8601String();
    }

    return computeGroupUnreadAsync(
      GroupUnreadComputeArgs(
        rows: rows,
        currentUserId: uid,
        lastReadIsoByGroupId: lastReadIsoByGroupId,
      ),
    );
  }

  /// Сообщения в каналах других пользователей (свой канал не учитываем).
  Future<int> _countChannelUnread(SupabaseClient client, String uid) async {
    final channelsRes = await client
        .from(SupabaseConstants.userChannelsTable)
        .select('id')
        .neq('owner_id', uid);
    final channelIds = (channelsRes as List)
        .map((e) => (e as Map<String, dynamic>)['id'] as String?)
        .whereType<String>()
        .toList();
    if (channelIds.isEmpty) return 0;

    final res = await client
        .from(SupabaseConstants.channelMessagesTable)
        .select('channel_id,created_at,kind')
        .inFilter('channel_id', channelIds)
        .order('created_at', ascending: false)
        .limit(_kMessagesListLimit);

    final rows = (res as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return 0;

    final lastReadIsoByChannelId = <String, String?>{};
    for (final id in channelIds) {
      lastReadIsoByChannelId[id] =
          _chatListStorage.getLastReadAt(id)?.toIso8601String();
    }

    return computeChannelUnreadAsync(
      ChannelUnreadComputeArgs(
        rows: rows,
        lastReadIsoByChannelId: lastReadIsoByChannelId,
      ),
    );
  }
}
