import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/utils/notification_badge_format.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/notification_unread_summary.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../notification_activity_peek_bus.dart';

/// Компактная плашка рядом с кнопкой уведомлений в AppBar ленты (после выбора вкладки «Публикации»).
class NotificationActivityPeekBar extends StatefulWidget {
  const NotificationActivityPeekBar({super.key});

  @override
  NotificationActivityPeekBarState createState() =>
      NotificationActivityPeekBarState();
}

class NotificationActivityPeekBarState extends State<NotificationActivityPeekBar> {
  Timer? _hideTimer;
  NotificationUnreadSummary? _summary;
  bool _visible = false;

  static const Duration _showDuration = Duration(milliseconds: 2600);

  late final NotificationActivityPeekBus _peekBus;

  @override
  void initState() {
    super.initState();
    _peekBus = context.read<NotificationActivityPeekBus>();
    _peekBus.publicationsTabPulse.addListener(_onPublicationsTabPulse);
  }

  void _onPublicationsTabPulse() {
    showBriefPeek();
  }

  @override
  void dispose() {
    _peekBus.publicationsTabPulse.removeListener(_onPublicationsTabPulse);
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> showBriefPeek() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) return;

    _hideTimer?.cancel();

    NotificationUnreadSummary? summary;
    try {
      summary = await context
          .read<NotificationsRepository>()
          .getUnreadSummary(userId);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    if (summary.totalUnread <= 0) return;

    setState(() {
      _summary = summary;
      _visible = true;
    });

    _hideTimer = Timer(_showDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  Future<void> _openNotifications() async {
    _hideTimer?.cancel();
    setState(() => _visible = false);
    await context.push('/notifications');
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) =>
          (prev is AuthAuthenticated) != (curr is AuthAuthenticated) ||
          (prev is AuthAuthenticated &&
              curr is AuthAuthenticated &&
              prev.user.id != curr.user.id),
      listener: (context, state) {
        _hideTimer?.cancel();
        setState(() {
          _visible = false;
          _summary = null;
        });
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.12, 0),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          );
        },
        child: !_visible || _summary == null
            ? const SizedBox.shrink(key: ValueKey('peek-off'))
            : Padding(
                key: const ValueKey('peek-on'),
                padding: const EdgeInsets.only(right: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _openNotifications,
                    borderRadius: BorderRadius.circular(18),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: ThemedContentSurface.scaffoldElevated,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: _CompactCountsRow(summary: _summary!),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CompactCountsRow extends StatelessWidget {
  const _CompactCountsRow({required this.summary});

  final NotificationUnreadSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MiniAvatarStack(urls: summary.previewAvatarUrls),
        const SizedBox(width: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (summary.unreadLikes > 0)
              _MiniStat(
                icon: Icons.favorite_rounded,
                count: summary.unreadLikes,
                color: const Color(0xFFE91E63),
              ),
            if (summary.unreadComments > 0) ...[
              if (summary.unreadLikes > 0) const SizedBox(width: 5),
              _MiniStat(
                icon: Icons.chat_bubble_rounded,
                count: summary.unreadComments,
                color: const Color(0xFF1565C0),
              ),
            ],
            if (summary.unreadReposts > 0) ...[
              if (summary.unreadLikes > 0 || summary.unreadComments > 0)
                const SizedBox(width: 5),
              _MiniStat(
                icon: Icons.repeat_rounded,
                count: summary.unreadReposts,
                color: const Color(0xFF6A1B9A),
              ),
            ],
            if (summary.unreadLikes == 0 &&
                summary.unreadComments == 0 &&
                summary.unreadReposts == 0 &&
                summary.totalUnread > 0) ...[
              Icon(
                Icons.notifications_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 3),
              Text(
                formatNotificationBadgeCount(summary.totalUnread),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      color: ThemedContentSurface.profileTextPrimary,
                    ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 2),
        Text(
          formatNotificationBadgeCount(count),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: ThemedContentSurface.profileTextPrimary,
              ),
        ),
      ],
    );
  }
}

class _MiniAvatarStack extends StatelessWidget {
  const _MiniAvatarStack({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    const size = 24.0;
    const overlap = 8.0;

    if (urls.isEmpty) {
      return Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(
          Icons.favorite_rounded,
          size: 14,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final n = urls.length.clamp(1, 3);
    return SizedBox(
      width: size + (n - 1) * overlap,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              left: i * overlap,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: urls[i],
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    memCacheWidth:
                        (size * MediaQuery.devicePixelRatioOf(context)).round(),
                    memCacheHeight:
                        (size * MediaQuery.devicePixelRatioOf(context)).round(),
                    placeholder: (context, url) => ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const SizedBox(width: size, height: size),
                    ),
                    errorWidget: (context, url, error) => ColoredBox(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: Icon(
                        Icons.person_rounded,
                        size: 14,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
