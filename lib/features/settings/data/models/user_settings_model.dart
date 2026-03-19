import 'package:tmr_tau/features/settings/domain/entities/user_settings_entity.dart';

/// Data model for `UserSettingsEntity`.
class UserSettingsModel extends UserSettingsEntity {
  const UserSettingsModel({
    required super.userId,
    required super.pushNotificationsEnabled,
    required super.emailNotificationsEnabled,
    required super.inAppNotificationsEnabled,
    required super.activityStatusEnabled,
    required super.storyVisibility,
    required super.postVisibility,
    required super.twoFactorEnabled,
    super.updatedAt,
  });

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    return null;
  }

  factory UserSettingsModel.fromJson(Map<String, dynamic> json) {
    return UserSettingsModel(
      userId: json['user_id'] as String,
      pushNotificationsEnabled:
          (json['push_notifications_enabled'] as bool?) ?? true,
      emailNotificationsEnabled:
          (json['email_notifications_enabled'] as bool?) ?? true,
      inAppNotificationsEnabled:
          (json['in_app_notifications_enabled'] as bool?) ?? true,
      activityStatusEnabled:
          (json['activity_status_enabled'] as bool?) ?? true,
      storyVisibility: (json['story_visibility'] as String?) ?? 'followers',
      postVisibility: (json['post_visibility'] as String?) ?? 'followers',
      twoFactorEnabled: (json['two_factor_enabled'] as bool?) ?? false,
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }
}

