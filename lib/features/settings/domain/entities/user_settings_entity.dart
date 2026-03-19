import 'package:equatable/equatable.dart';

/// User-level settings stored in Supabase (`public.user_settings`).
///
/// This entity contains only data (no networking / Supabase calls).
class UserSettingsEntity extends Equatable {
  const UserSettingsEntity({
    required this.userId,
    required this.pushNotificationsEnabled,
    required this.emailNotificationsEnabled,
    required this.inAppNotificationsEnabled,
    required this.activityStatusEnabled,
    required this.storyVisibility,
    required this.postVisibility,
    required this.twoFactorEnabled,
    this.updatedAt,
  });

  final String userId;

  final bool pushNotificationsEnabled;
  final bool emailNotificationsEnabled;
  final bool inAppNotificationsEnabled;

  /// Shows "active now"/activity status.
  final bool activityStatusEnabled;

  /// Allowed values:
  /// - `everyone`
  /// - `followers`
  /// - `only_me`
  final String storyVisibility;

  /// Allowed values:
  /// - `public`
  /// - `followers`
  /// - `only_me`
  final String postVisibility;

  /// 2FA is treated as a preference flag for now.
  final bool twoFactorEnabled;

  final DateTime? updatedAt;

  UserSettingsEntity copyWith({
    String? userId,
    bool? pushNotificationsEnabled,
    bool? emailNotificationsEnabled,
    bool? inAppNotificationsEnabled,
    bool? activityStatusEnabled,
    String? storyVisibility,
    String? postVisibility,
    bool? twoFactorEnabled,
    DateTime? updatedAt,
  }) {
    return UserSettingsEntity(
      userId: userId ?? this.userId,
      pushNotificationsEnabled:
          pushNotificationsEnabled ?? this.pushNotificationsEnabled,
      emailNotificationsEnabled:
          emailNotificationsEnabled ?? this.emailNotificationsEnabled,
      inAppNotificationsEnabled:
          inAppNotificationsEnabled ?? this.inAppNotificationsEnabled,
      activityStatusEnabled: activityStatusEnabled ?? this.activityStatusEnabled,
      storyVisibility: storyVisibility ?? this.storyVisibility,
      postVisibility: postVisibility ?? this.postVisibility,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        pushNotificationsEnabled,
        emailNotificationsEnabled,
        inAppNotificationsEnabled,
        activityStatusEnabled,
        storyVisibility,
        postVisibility,
        twoFactorEnabled,
        updatedAt,
      ];
}

