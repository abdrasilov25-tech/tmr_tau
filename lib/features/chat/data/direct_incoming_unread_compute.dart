import 'package:flutter/foundation.dart' show compute;

/// Аргументы для [computeTotalDirectUnreadInIsolate] (тот же смысл, что и список чатов).
class DirectUnreadComputeArgs {
  const DirectUnreadComputeArgs({
    required this.rows,
    required this.currentUserId,
    required this.lastReadIsoByPeer,
  });

  final List<Map<String, dynamic>> rows;
  final String currentUserId;
  final Map<String, String?> lastReadIsoByPeer;
}

/// Сумма входящих непрочитанных по диалогам (логика совпадает с [ChatsPage] / compute для списка).
int computeTotalDirectUnreadInIsolate(DirectUnreadComputeArgs args) {
  final rows = args.rows;
  final currentUserId = args.currentUserId;
  final lastReadIsoByPeer = args.lastReadIsoByPeer;

  final Map<String, int> unreadByPeer = {};
  final Map<String, DateTime?> lastIncomingByPeer = {};

  for (final json in rows) {
    final senderId = json['sender_id'] as String;
    final receiverId = json['receiver_id'] as String;
    final peerId = senderId == currentUserId ? receiverId : senderId;
    final createdAt = DateTime.parse(json['created_at'] as String);

    final isIncoming = senderId == peerId && receiverId == currentUserId;
    if (!isIncoming) continue;

    final lastReadStr = lastReadIsoByPeer[peerId];
    final lastRead = lastReadStr != null ? DateTime.tryParse(lastReadStr) : null;

    final prevIncoming = lastIncomingByPeer[peerId];
    if (prevIncoming == null || createdAt.isAfter(prevIncoming)) {
      lastIncomingByPeer[peerId] = createdAt;
    }
    if (lastRead == null || createdAt.isAfter(lastRead)) {
      unreadByPeer[peerId] = (unreadByPeer[peerId] ?? 0) + 1;
    }
  }

  var sum = 0;
  for (final v in unreadByPeer.values) {
    sum += v;
  }
  return sum;
}

Future<int> computeTotalDirectUnreadAsync(DirectUnreadComputeArgs args) {
  return compute(computeTotalDirectUnreadInIsolate, args);
}
