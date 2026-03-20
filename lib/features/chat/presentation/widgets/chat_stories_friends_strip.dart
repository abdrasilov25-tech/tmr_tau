import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../stories/domain/entities/story_group_entity.dart';

class ChatStoriesFriendsStrip extends StatelessWidget {
  const ChatStoriesFriendsStrip({
    super.key,
    required this.groups,
    required this.newStoriesByUserId,
    required this.onStoryTap,
  });

  final List<StoryGroupEntity> groups;

  /// `userId -> true` means show red “new” ring.
  final Map<String, bool> newStoriesByUserId;

  /// Called when user taps a friend's story.
  final void Function(StoryGroupEntity group) onStoryTap;

  @override
  Widget build(BuildContext context) {
    if (groups.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 102,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final g = groups[index];
          final isNew = newStoriesByUserId[g.userId] == true;
          return _FriendStoryCircle(
            group: g,
            isNew: isNew,
            onTap: () => onStoryTap(g),
          );
        },
      ),
    );
  }
}

class _FriendStoryCircle extends StatelessWidget {
  const _FriendStoryCircle({
    required this.group,
    required this.isNew,
    required this.onTap,
  });

  final StoryGroupEntity group;
  final bool isNew;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = isNew ? Colors.redAccent : Colors.white24;
    // Целочисленная толщина границы уменьшает «смаз» из-за полу-пикселей.
    final borderWidth = isNew ? 3.0 : 2.0;
    const outerSize = 56.0;
    final innerRadius = (outerSize - borderWidth * 2) / 2;
    final innerDiameter = innerRadius * 2;

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: outerSize,
              height: outerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: borderColor, width: borderWidth),
              ),
              child: ClipOval(
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  width: innerDiameter,
                  height: innerDiameter,
                  child: _StoryAvatarImage(
                    imageUrl: group.userAvatarUrl,
                    fallbackText: group.userName ?? 'Пользователь',
                    diameter: innerDiameter,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 68,
              child: Text(
                group.userName ?? 'Пользователь',
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

