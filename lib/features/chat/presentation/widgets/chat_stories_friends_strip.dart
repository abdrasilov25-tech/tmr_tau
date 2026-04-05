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
    required this.storyNotesByUserId,
    this.storyLocationsByUserId = const <String, String>{},
    this.enableNotes = true,
    required this.onAddStoryTap,
    required this.onStoryTap,
    required this.onOwnNoteTap,
  });

  final List<StoryGroupEntity> groups;

  /// `userId -> true` means show red “new” ring.
  final Map<String, bool> newStoriesByUserId;
  final String? currentUserId;

  /// Аватар из профиля (AuthBloc): для «Ваша история», когда нет группы сторис или в ней нет URL.
  final String? currentUserAvatarUrl;
  final Map<String, String> storyNotesByUserId;
  final Map<String, String> storyLocationsByUserId;
  final bool enableNotes;
  final VoidCallback onAddStoryTap;

  /// Called when user taps a friend's story.
  final void Function(StoryGroupEntity group) onStoryTap;
  final void Function(String currentNote) onOwnNoteTap;

  @override
  Widget build(BuildContext context) {
    // Нет сторис у других — всё равно показываем «Ваша история» + плюс (добавить).
    if (groups.isEmpty) {
      if (currentUserId == null) {
        return const SizedBox.shrink();
      }
      return SizedBox(
        height: enableNotes ? 190 : 128,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: [
            _FriendStoryCircle(
              group: null,
              profileAvatarUrl: currentUserAvatarUrl,
              fallbackLabel: 'Ваша история',
              ringState: _StoryRingState.seen,
              showPlusBadge: true,
              note: storyNotesByUserId[currentUserId!] ?? '',
              location: storyLocationsByUserId[currentUserId!] ?? '',
              isCurrentUser: true,
              enableNotes: enableNotes,
              onTap: onAddStoryTap,
              onPlusTap: onAddStoryTap,
              onNoteTap: () => onOwnNoteTap(storyNotesByUserId[currentUserId!] ?? ''),
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
      height: enableNotes ? 176 : 116,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
              note: storyNotesByUserId[currentUserId] ?? '',
              location: storyLocationsByUserId[currentUserId] ?? '',
              isCurrentUser: true,
              enableNotes: enableNotes,
              onTap: ownGroup == null ? onAddStoryTap : () => onStoryTap(ownGroup),
              onPlusTap: onAddStoryTap,
              onNoteTap: () => onOwnNoteTap(storyNotesByUserId[currentUserId] ?? ''),
            ),
          ...otherGroups.map((g) {
            final isNew = newStoriesByUserId[g.userId] == true;
            return _FriendStoryCircle(
              group: g,
              ringState: isNew ? _StoryRingState.unseen : _StoryRingState.seen,
              // Instagram-like behavior: show other users' notes in the strip.
              note: storyNotesByUserId[g.userId] ?? '',
              location: storyLocationsByUserId[g.userId] ?? '',
              enableNotes: enableNotes,
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
    this.note = '',
    this.location = '',
    this.isCurrentUser = false,
    this.enableNotes = true,
    required this.onTap,
    this.onPlusTap,
    this.onNoteTap,
  });

  final StoryGroupEntity? group;

  /// Только для своего слота: если в [group] нет аватара — берём из профиля.
  final String? profileAvatarUrl;
  final String? fallbackLabel;
  final _StoryRingState ringState;
  final bool showPlusBadge;
  final String note;
  final String location;
  final bool isCurrentUser;
  final bool enableNotes;
  final VoidCallback onTap;
  final VoidCallback? onPlusTap;
  final VoidCallback? onNoteTap;

  @override
  Widget build(BuildContext context) {
    final label = fallbackLabel ?? group?.userName ?? 'Пользователь';
    final fromGroup = group?.userAvatarUrl;
    final imageUrl = (fromGroup != null && fromGroup.isNotEmpty)
        ? fromGroup
        : profileAvatarUrl;
    const outerSize = 72.0;
    const ringWidth = 2.5;
    final innerRadius = (outerSize - ringWidth * 2 - 3) / 2;
    final innerDiameter = innerRadius * 2;
    final ringGradient = ringState == _StoryRingState.unseen
        ? const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Color(0xFFFAD961), // yellow
              Color(0xFFF76B1C), // orange
              Color(0xFFDD2476), // pink-red
              Color(0xFF833AB4), // purple
            ],
            stops: [0.0, 0.33, 0.66, 1.0],
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFBDBDBD), Color(0xFF9E9E9E)],
          );

    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (enableNotes)
              SizedBox(
                height: 28,
                child: note.trim().isNotEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: GestureDetector(
                          onTap: onNoteTap ?? onTap,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 88),
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFFFFFF),
                                  Color(0xFFF3F4F6),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0x22000000)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Text(
                              note.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11.5,
                                    color: const Color(0xFF0B1220),
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.15,
                                    height: 1.05,
                                  ),
                            ),
                          ),
                        ),
                      )
                    : (isCurrentUser
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: GestureDetector(
                              onTap: onNoteTap,
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 88),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFFF8FAFD),
                                      Color(0xFFEFF3FA),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0x1F1E88E5)),
                                ),
                                child: Text(
                                  'Заметка',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontSize: 10.8,
                                        color: const Color(0xFF1F2937),
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink()),
              ),
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
              width: 78,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
              ),
            ),
            if (enableNotes && location.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              SizedBox(
                width: 82,
                child: Text(
                  '📍 ${location.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
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

