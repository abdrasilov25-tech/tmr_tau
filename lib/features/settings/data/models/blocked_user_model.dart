import 'package:tmr_tau/features/settings/domain/entities/blocked_user_entity.dart';

class BlockedUserModel extends BlockedUserEntity {
  const BlockedUserModel({
    required super.blockedUserId,
    super.blockedUserName,
    super.blockedUserAvatarUrl,
    required super.blockedAt,
  });

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    // Fallback for PostgREST numeric timestamps.
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    throw FormatException('Invalid datetime: $value');
  }

  factory BlockedUserModel.fromJson(Map<String, dynamic> json) {
    return BlockedUserModel(
      blockedUserId: json['blocked_user_id'] as String,
      blockedUserName: json['blocked_user_name'] as String?,
      blockedUserAvatarUrl: json['blocked_user_avatar_url'] as String?,
      blockedAt: _parseDateTime(json['created_at']),
    );
  }
}

