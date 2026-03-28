import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/widgets/cached_avatar.dart';

/// Многоразовый виджет аватара с навигацией на профиль.
///
/// Используй везде где нужен кликабельный аватар:
/// ```dart
/// UserAvatarTap(
///   userId: post.userId,
///   avatarUrl: post.userAvatarUrl,
///   radius: 18,
/// )
/// ```
class UserAvatarTap extends StatelessWidget {
  const UserAvatarTap({
    super.key,
    required this.userId,
    this.avatarUrl,
    this.radius = 18,
    this.currentUserId,
    this.onTap,
  });

  final String userId;
  final String? avatarUrl;
  final double radius;

  /// Если текущий пользователь — переходим на /profile/me, иначе /profile/:id.
  final String? currentUserId;

  /// Переопределяет стандартную навигацию если задан.
  final VoidCallback? onTap;

  void _navigate(BuildContext context) {
    if (onTap != null) {
      onTap!();
      return;
    }
    // Переход на профиль продавца/пользователя через go_router
    context.push('/profile/$userId');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigate(context),
      behavior: HitTestBehavior.opaque,
      child: CachedAvatar(
        imageUrl: avatarUrl,
        radius: radius,
        enableLightboxOnTap: false,
      ),
    );
  }
}

/// Кликабельное имя пользователя (текст).
class UsernameTap extends StatelessWidget {
  const UsernameTap({
    super.key,
    required this.userId,
    required this.username,
    this.style,
    this.onTap,
  });

  final String userId;
  final String username;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => context.push('/profile/$userId'),
      behavior: HitTestBehavior.opaque,
      child: Text(
        username,
        style: style ??
            const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: Colors.white,
            ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
