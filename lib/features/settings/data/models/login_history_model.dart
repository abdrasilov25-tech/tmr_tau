import 'package:tmr_tau/features/settings/domain/entities/login_history_entity.dart';

class LoginHistoryModel extends LoginHistoryEntity {
  const LoginHistoryModel({
    required super.id,
    required super.userId,
    required super.loggedInAt,
    super.ipAddress,
    super.userAgent,
  });

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    return DateTime.fromMillisecondsSinceEpoch(value as int);
  }

  factory LoginHistoryModel.fromJson(Map<String, dynamic> json) {
    return LoginHistoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      loggedInAt: _parseDateTime(json['logged_in_at'] ?? json['created_at']),
      ipAddress: json['ip_address'] as String?,
      userAgent: json['user_agent'] as String?,
    );
  }
}

