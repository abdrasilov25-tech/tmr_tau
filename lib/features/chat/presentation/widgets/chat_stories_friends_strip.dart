import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../stories/domain/entities/story_group_entity.dart';

class ChatStoriesFriendsStrip extends StatelessWidget {
  const ChatStoriesFriendsStrip({
    super.key,
    required this.groups,
    required this.newStoriesByUserId,
    required this.currentUserId,
    this.currentUserAvatarUrl,
    required this.onAddStoryTap,
    required this.onStoryTap,
  });

  final List<StoryGroupEntity> groups;

  /// `userId -> true` means show red “new” ring.
  final Map<String, bool> newStoriesByUserId;
  final String? currentUserId;

  /// Аватар из профиля (AuthBloc): для «Ваша история», когда нет группы сторис или в ней нет URL.
  final String? currentUserAvatarUrl;
  final VoidCallback onAddStoryTap;

  /// Called when user taps a friend's story.
  final void Function(StoryGroupEntity group) onStoryTap;

  @override
  Widget build(BuildContext context) {
    // Нет сторис у других — всё равно показываем «Ваша история» + плюс (добавить).
    if (groups.isEmpty) {
      if (currentUserId == null) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        height: 102,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            _FriendStoryCircle(
              group: null,
              profileAvatarUrl: currentUserAvatarUrl,
              fallbackLabel: 'Ваша история',
              ringState: _StoryRingState.seen,
              showPlusBadge: true,
              onTap: onAddStoryTap,
              onPlusTap: onAddStoryTap,
            ),
          ],
        ),
      );
    }
    final ownGroup = currentUserId == null
        ? null
        : groups.cast<StoryGroupEntity?>().firstWhere(
              (g) => g?.userId == currentUserId,
              orElse: () => null,
            );
    final otherGroups = currentUserId == null
        ? groups
        : groups.where((g) => g.userId != currentUserId).toList(growable: false);

    return SizedBox(
      height: 102,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          if (currentUserId != null)
            _FriendStoryCircle(
              group: ownGroup,
              profileAvatarUrl: currentUserAvatarUrl,
              fallbackLabel: 'Ваша история',
              ringState: ownGroup == null
                  ? _StoryRingState.seen
                  : (newStoriesByUserId[ownGroup.userId] == true
                        ? _StoryRingState.unseen
                        : _StoryRingState.seen),
              showPlusBadge: true,
              onTap: ownGroup == null ? onAddStoryTap : () => onStoryTap(ownGroup),
              onPlusTap: onAddStoryTap,
            ),
          ...otherGroups.map((g) {
            final isNew = newStoriesByUserId[g.userId] == true;
            return _FriendStoryCircle(
              group: g,
              ringState: isNew ? _StoryRingState.unseen : _StoryRingState.seen,
              onTap: () => onStoryTap(g),
            );
          }),
        ],
      ),
    );
  }
}

enum _StoryRingState { unseen, seen }

class _FriendStoryCircle extends StatelessWidget {
  const _FriendStoryCircle({
    this.group,
    this.profileAvatarUrl,
    this.fallbackLabel,
    required this.ringState,
    this.showPlusBadge = false,
    required this.onTap,
    this.onPlusTap,
  });

  final StoryGroupEntity? group;

  /// Только для своего слота: если в [group] нет аватара — берём из профиля.
  final String? profileAvatarUrl;
  final String? fallbackLabel;
  final _StoryRingState ringState;
  final bool showPlusBadge;
  final VoidCallback onTap;
  final VoidCallback? onPlusTap;

  @override
  Widget build(BuildContext context) {
    final label = fallbackLabel ?? group?.userName ?? 'Пользователь';
    final fromGroup = group?.userAvatarUrl;
    final imageUrl = (fromGroup != null && fromGroup.isNotEmpty)
        ? fromGroup
        : profileAvatarUrl;
    const outerSize = 56.0;
    const ringWidth = 2.8;
    final innerRadius = (outerSize - ringWidth * 2) / 2;
    final innerDiameter = innerRadius * 2;
    final ringGradient = ringState == _StoryRingState.unseen
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFF6F61), Color(0xFFE53935)],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF66BB6A), Color(0xFF2E7D32)],
          );

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: outerSize,
              height: outerSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: outerSize,
                    height: outerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: ringGradient,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(ringWidth),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).scaffoldBackgroundColor,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox(
                            width: innerDiameter,
                            height: innerDiameter,
                            child: _StoryAvatarImage(
                              imageUrl: imageUrl,
                              fallbackText: label,
                              diameter: innerDiameter,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showPlusBadge)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onPlusTap ?? onTap,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E88E5),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.add, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 68,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryAvatarImage extends StatelessWidget {
  const _StoryAvatarImage({
    required this.imageUrl,
    required this.fallbackText,
    required this.diameter,
  });

  final String? imageUrl;
  final String fallbackText;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final fallback = fallbackText.isNotEmpty ? fallbackText[0].toUpperCase() : '?';

    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(
          fallback,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      width: diameter,
      height: diameter,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(
          fallback,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Text(
          fallback,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
  }
}

