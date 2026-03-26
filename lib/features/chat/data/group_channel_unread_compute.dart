import 'package:flutter/foundation.dart' show compute;

/// Сообщения групповых чатов + отметки прочитанного по [groupId].
class GroupUnreadComputeArgs {
  const GroupUnreadComputeArgs({
    required this.rows,
    required this.currentUserId,
    required this.lastReadIsoByGroupId,
  });

  final List<Map<String, dynamic>> rows;
  final String currentUserId;
  final Map<String, String?> lastReadIsoByGroupId;
}

int computeGroupUnreadInIsolate(GroupUnreadComputeArgs args) {
  final rows = args.rows;
  final uid = args.currentUserId;
  final lastReadIsoByGroupId = args.lastReadIsoByGroupId;
  final Map<String, int> unreadByGroup = {};

  for (final json in rows) {
    final kind = json['kind'] as String? ?? 'text';
    if (kind != 'text') continue;
    final groupId = json['group_id'] as String;
    final senderId = json['sender_id'] as String;
    final createdAt = DateTime.parse(json['created_at'] as String);
    if (senderId == uid) continue;

    final lastReadStr = lastReadIsoByGroupId[groupId];
    final lastRead = lastReadStr != null ? DateTime.tryParse(lastReadStr) : null;
    if (lastRead == null || createdAt.isAfter(lastRead)) {
      unreadByGroup[groupId] = (unreadByGroup[groupId] ?? 0) + 1;
    }
  }

  var sum = 0;
  for (final v in unreadByGroup.values) {
    sum += v;
  }
  return sum;
}

Future<int> computeGroupUnreadAsync(GroupUnreadComputeArgs args) {
  return compute(computeGroupUnreadInIsolate, args);
}

/// Посты в чужих каналах (все сообщения считаются «входящими» для подписчика).
class ChannelUnreadComputeArgs {
  const ChannelUnreadComputeArgs({
    required this.rows,
    required this.lastReadIsoByChannelId,
  });

  final List<Map<String, dynamic>> rows;
  final Map<String, String?> lastReadIsoByChannelId;
}

int computeChannelUnreadInIsolate(ChannelUnreadComputeArgs args) {
  final rows = args.rows;
  final lastReadIsoByChannelId = args.lastReadIsoByChannelId;
  var count = 0;
  for (final json in rows) {
    final kind = json['kind'] as String? ?? 'text';
    if (kind != 'text') continue;
    final channelId = json['channel_id'] as String;
    final createdAt = DateTime.parse(json['created_at'] as String);
    final lastReadStr = lastReadIsoByChannelId[channelId];
    final lastRead = lastReadStr != null ? DateTime.tryParse(lastReadStr) : null;
    if (lastRead == null || createdAt.isAfter(lastRead)) {
      count++;
    }
  }
  return count;
}

Future<int> computeChannelUnreadAsync(ChannelUnreadComputeArgs args) {
  return compute(computeChannelUnreadInIsolate, args);
}
