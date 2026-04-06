import 'package:flutter/material.dart';

import '../../../../core/feedback/feedback_manager.dart';

/// Красная «Подписаться» / зелёная «Отписаться» для авторов в лентах.
class PostAuthorFollowPill extends StatelessWidget {
  const PostAuthorFollowPill({
    super.key,
    required this.isFollowing,
    required this.onTap,
    this.compact = false,
  });

  final bool isFollowing;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bg = isFollowing ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
    final label = isFollowing ? 'Отписаться' : 'Подписаться';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isFollowing) {
            FeedbackManager.instance.buttonTap();
          } else {
            FeedbackManager.instance.success();
          }
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 11,
            vertical: compact ? 4 : 5,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}
