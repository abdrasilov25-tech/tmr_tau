import 'package:tmr_tau/features/settings/domain/entities/user_session_entity.dart';

class UserSessionModel extends UserSessionEntity {
  const UserSessionModel({
    required super.id,
    required super.userId,
    required super.createdAt,
    required super.lastSeenAt,
    super.device,
    super.ipAddress,
  });

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  factory UserSessionModel.fromJson(Map<String, dynamic> json) {
    return UserSessionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      createdAt: _parseDateTime(json['created_at']),
      lastSeenAt: _parseDateTime(json['last_seen_at'] ?? json['created_at']),
      device: json['device'] as String?,
      ipAddress: json['ip_address'] as String?,
    );
  }
}

