import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/media/cached_video_controller.dart';
import '../../../../core/media/global_video_audio_state.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/story_entity.dart';
import '../../domain/entities/story_overlay_item.dart';
import '../../domain/entities/story_group_entity.dart';
import '../../domain/repositories/stories_repository.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../widgets/story_music_sticker.dart';
import '../widgets/story_overlays_stack.dart';

/// Единый формат сторис (как в Instagram — вертикальный 9:16).
const double _storyAspectRatio = 9 / 16;

/// Полноэкранный просмотр сторис в стиле Instagram.
/// [groups] — список групп (по пользователям), [initialGroupIndex] — с какой группы начать.
class StoryViewerPage extends StatefulWidget {
  const StoryViewerPage({
    super.key,
    required this.groups,
    this.initialGroupIndex = 0,
  });

  final List<StoryGroupEntity> groups;
  final int initialGroupIndex;

  @override
  State<StoryViewerPage> createState() => _StoryViewerPageState();
}

class _StoryViewerPageState extends State<StoryViewerPage> {
  late PageController _groupPageController;
  late List<PageController> _storyPageControllers;
  late int _currentGroupIndex;
  Timer? _timer;
  static const Duration _photoStoryDuration = Duration(milliseconds: 6500);
  static const Duration _videoStoryDuration = Duration(seconds: 8);
  Duration _remainingDuration = _photoStoryDuration;
  DateTime? _timerStartedAt;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _currentGroupIndex = _safeInitialGroupIndex();
    _groupPageController = PageController(initialPage: _currentGroupIndex);
    _storyPageControllers = List.generate(
      widget.groups.length,
      (i) => PageController(initialPage: 0),
    );
    if (widget.groups.isNotEmpty) {
      _startTimer();
    }
  }

  int _safeInitialGroupIndex() {
    if (widget.groups.isEmpty) return 0;
    final maxIndex = widget.groups.length - 1;
    return widget.initialGroupIndex.clamp(0, maxIndex);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _groupPageController.dispose();
    for (final c in _storyPageControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _startTimer() {
    if (_isPaused) return;
    _timer?.cancel();
    _timerStartedAt = DateTime.now();
    _timer = Timer(_remainingDuration, () {
      if (!mounted) return;
      _remainingDuration = _durationForStory();
      _goNext();
    });
  }

  Duration _durationForStory({int? groupIndex, int? storyIndex}) {
    if (widget.groups.isEmpty) return _photoStoryDuration;
    final g = (groupIndex ?? _currentGroupIndex).clamp(0, widget.groups.length - 1);
    final group = widget.groups[g];
    if (group.stories.isEmpty) return _photoStoryDuration;
    final maxIdx = group.stories.length - 1;
    final fallbackIndex = _storyPageControllers[g].hasClients
        ? (_storyPageControllers[g].page?.round() ?? 0)
        : 0;
    final s = (storyIndex ?? fallbackIndex).clamp(0, maxIdx);
    final story = group.stories[s];
    final hasVideo = (story.videoUrl ?? '').isNotEmpty;
    if (hasVideo) {
      final sec = story.videoDurationSeconds;
      if (sec > 0) {
        return Duration(seconds: sec.clamp(1, _maxVideoStorySeconds));
      }
      return _videoStoryDuration;
    }
    return _photoStoryDuration;
  }

  static const int _maxVideoStorySeconds = 120;

  void _pausePlayback() {
    if (_isPaused) return;
    _isPaused = true;
    final startedAt = _timerStartedAt;
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      final remainingMs =
          _remainingDuration.inMilliseconds - elapsed.inMilliseconds;
      _remainingDuration = Duration(
        milliseconds: remainingMs < 0 ? 0 : remainingMs,
      );
    }
    _timer?.cancel();
    if (mounted) setState(() {});
  }

  void _resumePlayback() {
    if (!_isPaused) return;
    _isPaused = false;
    if (_remainingDuration.inMilliseconds <= 0) {
      _remainingDuration = _durationForStory();
      _goNext();
      return;
    }
    _startTimer();
    if (mounted) setState(() {});
  }

  void _goNext() {
    if (widget.groups.isEmpty) {
      context.popOrGoHomeFeed();
      return;
    }
    final group = widget.groups[_currentGroupIndex];
    final storyController = _storyPageControllers[_currentGroupIndex];
    final currentStoryPage = storyController.page?.round() ?? 0;

    if (currentStoryPage < group.stories.length - 1) {
      if (storyController.hasClients) {
        storyController.nextPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
      _remainingDuration = _durationForStory(
        groupIndex: _currentGroupIndex,
        storyIndex: currentStoryPage + 1,
      );
      _startTimer();
    } else if (_currentGroupIndex < widget.groups.length - 1) {
      _currentGroupIndex++;
      if (_groupPageController.hasClients) {
        _groupPageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      final nextController = _storyPageControllers[_currentGroupIndex];
      if (nextController.hasClients) {
        nextController.jumpToPage(0);
      }
      _remainingDuration = _durationForStory(
        groupIndex: _currentGroupIndex,
        storyIndex: 0,
      );
      _startTimer();
    } else {
      context.popOrGoHomeFeed();
    }
  }

  void _goPrev() {
    if (widget.groups.isEmpty) {
      context.popOrGoHomeFeed();
      return;
    }
    final storyController = _storyPageControllers[_currentGroupIndex];
    final currentStoryPage = storyController.page?.round() ?? 0;

    if (currentStoryPage > 0) {
      if (storyController.hasClients) {
        storyController.previousPage(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
      }
      _remainingDuration = _durationForStory(
        groupIndex: _currentGroupIndex,
        storyIndex: currentStoryPage - 1,
      );
      _startTimer();
    } else if (_currentGroupIndex > 0) {
      _currentGroupIndex--;
      final prevGroup = widget.groups[_currentGroupIndex];
      if (_groupPageController.hasClients) {
        _groupPageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
      final prevController = _storyPageControllers[_currentGroupIndex];
      if (prevController.hasClients) {
        prevController.jumpToPage(prevGroup.stories.length - 1);
      }
      _remainingDuration = _durationForStory(
        groupIndex: _currentGroupIndex,
        storyIndex: prevGroup.stories.length - 1,
      );
      _startTimer();
    } else {
      context.popOrGoHomeFeed();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.groups.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Нет историй',
            style: TextStyle(color: Colors.grey.shade400),
          ),
        ),
      );
    }
    final authState = context.read<AuthBloc>().state;
    final currentUserId = authState is AuthAuthenticated ? authState.user.id : null;
    final storiesRepo = context.read<StoriesRepository>();

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 350) {
            context.popOrGoHomeFeed();
          }
        },
        child: PageView.builder(
          controller: _groupPageController,
          scrollDirection: Axis.vertical,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.groups.length,
          onPageChanged: (i) {
            setState(() => _currentGroupIndex = i);
            _remainingDuration = _durationForStory(groupIndex: i, storyIndex: 0);
            _startTimer();
          },
          itemBuilder: (context, groupIndex) {
            final group = widget.groups[groupIndex];
            return _StoryGroupView(
              group: group,
              storyController: _storyPageControllers[groupIndex],
              onNext: _goNext,
              onPrev: _goPrev,
              onPause: _pausePlayback,
              onResume: _resumePlayback,
              isPaused: _isPaused,
              currentUserId: currentUserId,
              storiesRepository: storiesRepo,
            );
          },
        ),
      ),
    );
  }
}

class _StoryGroupView extends StatefulWidget {
  const _StoryGroupView({
    required this.group,
    required this.storyController,
    required this.onNext,
    required this.onPrev,
    required this.onPause,
    required this.onResume,
    required this.isPaused,
    this.currentUserId,
    required this.storiesRepository,
  });

  final StoryGroupEntity group;
  final PageController storyController;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final bool isPaused;
  final String? currentUserId;
  final StoriesRepository storiesRepository;

  @override
  State<_StoryGroupView> createState() => _StoryGroupViewState();
}

class _StoryGroupViewState extends State<_StoryGroupView> {
  /// Кольцо быстрых реакций как в Instagram (сердце — отдельно, крупнее по центру).
  static const List<String> _quickReactionsRing = [
    '😂',
    '😮',
    '😍',
    '😢',
    '👏',
    '🔥',
  ];
  static const String _storyDmPrefix = '__story__';
  int _currentIndex = 0;
  final _replyController = TextEditingController();
  final _replyFocusNode = FocusNode();
  bool _sendingReply = false;
  bool _showReplyComposer = false;
  final Set<String> _markedViewedIds = <String>{};
  int _viewsCount = 0;
  bool _viewsLoading = false;

  @override
  void initState() {
    super.initState();
    _markCurrentStoryViewed();
    _loadViewsCount();
    _replyFocusNode.addListener(_handleReplyFocusChange);
  }

  @override
  void didUpdateWidget(covariant _StoryGroupView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.userId != widget.group.userId) {
      _currentIndex = 0;
      _markCurrentStoryViewed();
      _loadViewsCount();
    }
  }

  @override
  void dispose() {
    _replyFocusNode
      ..removeListener(_handleReplyFocusChange)
      ..dispose();
    _replyController.dispose();
    super.dispose();
  }

  StoryEntity get _currentStory => widget.group.stories[_currentIndex];
  bool get _isOwnStory => widget.currentUserId != null && widget.group.userId == widget.currentUserId;

  Duration _storyBarDuration() {
    final s = _currentStory;
    final hasVideo = (s.videoUrl ?? '').isNotEmpty;
    if (hasVideo) {
      final sec = s.videoDurationSeconds;
      if (sec > 0) {
        return Duration(seconds: sec.clamp(1, 120));
      }
      return const Duration(seconds: 8);
    }
    return const Duration(milliseconds: 6500);
  }

  void _handleReplyFocusChange() {
    if (_replyFocusNode.hasFocus) {
      widget.onPause();
    } else if (!_sendingReply) {
      widget.onResume();
    }
  }

  void _pauseForInteraction() {
    widget.onPause();
  }

  void _openComposer() {
    setState(() => _showReplyComposer = true);
    _pauseForInteraction();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _replyFocusNode.requestFocus();
    });
  }

  void _resumeAfterInteractionIfPossible() {
    if (!_replyFocusNode.hasFocus && !_showReplyComposer) {
      widget.onResume();
    }
  }

  Future<void> _loadViewsCount() async {
    if (!_isOwnStory || widget.group.stories.isEmpty) return;
    setState(() => _viewsLoading = true);
    try {
      final count = await widget.storiesRepository.getStoryViewsCount(
        _currentStory.id,
      );
      if (!mounted) return;
      setState(() => _viewsCount = count);
    } catch (e) {
      if (!mounted) return;
      setState(() => _viewsCount = 0);
    } finally {
      if (mounted) setState(() => _viewsLoading = false);
    }
  }

  Future<void> _showViewersSheet() async {
    if (!_isOwnStory) return;
    try {
      final viewers = await widget.storiesRepository.getStoryViews(
        _currentStory.id,
      );
      if (!mounted) return;
      showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 360,
            child: viewers.isEmpty
                ? const Center(child: Text('Пока никто не посмотрел'))
                : ListView.separated(
                    itemCount: viewers.length,
                    separatorBuilder: (_, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final v = viewers[index];
                      final time =
                          '${v.viewedAt.hour.toString().padLeft(2, '0')}:${v.viewedAt.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        leading: CachedAvatar(
                          imageUrl: v.viewerAvatarUrl,
                          radius: 18,
                          fallbackText: v.viewerName,
                        ),
                        title: Text(v.viewerName ?? 'Пользователь'),
                        subtitle: Text('Просмотрено в $time'),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          context.push('/profile/${v.viewerId}');
                        },
                      );
                    },
                  ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить просмотры')),
      );
    }
  }

  Future<void> _markCurrentStoryViewed() async {
    final viewerId = widget.currentUserId;
    if (viewerId == null || _isOwnStory || widget.group.stories.isEmpty) return;
    final storyId = _currentStory.id;
    if (_markedViewedIds.contains(storyId)) return;
    _markedViewedIds.add(storyId);
    try {
      await widget.storiesRepository.markStoryViewed(
        storyId: storyId,
        viewerId: viewerId,
      );
    } catch (e) {
      // Viewing metrics should never break story playback.
    }
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || widget.currentUserId == null || _sendingReply) return;
    _pauseForInteraction();
    setState(() => _sendingReply = true);
    try {
      await widget.storiesRepository.addStoryReply(
        storyId: _currentStory.id,
        userId: widget.currentUserId!,
        text: text,
      );
      await _createStoryNotification(
        type: 'story_reply',
        title: 'Ответ на сторис',
        body: text,
      );
      await _sendToDirect(kind: 'reply', payload: text);
      if (mounted) {
        _replyController.clear();
        setState(() => _showReplyComposer = false);
        _replyFocusNode.unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ответ отправлен'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось отправить')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingReply = false);
        _resumeAfterInteractionIfPossible();
      }
    }
  }

  Future<void> _sendQuickReaction(String emoji) async {
    if (widget.currentUserId == null || _sendingReply) return;
    _pauseForInteraction();
    setState(() => _sendingReply = true);
    try {
      await widget.storiesRepository.addStoryReply(
        storyId: _currentStory.id,
        userId: widget.currentUserId!,
        text: emoji,
      );
      await _createStoryNotification(
        type: 'story_like',
        title: 'Реакция на сторис',
        body: emoji,
      );
      await _sendToDirect(kind: 'reaction', payload: emoji);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Реакция $emoji отправлена'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить реакцию')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingReply = false);
        _resumeAfterInteractionIfPossible();
      }
    }
  }

  Future<void> _shareCurrentStory() async {
    if (widget.currentUserId == null) return;
    _pauseForInteraction();
    try {
      final users = await _loadFollowingUsers();
      if (!mounted) return;
      if (users.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('У вас пока нет подписок')),
        );
        _resumeAfterInteractionIfPossible();
        return;
      }
      final picked = await showModalBottomSheet<_StoryShareUser>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text(
                  'Поделиться сторис',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: users.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final u = users[index];
                      return ListTile(
                        leading: CachedAvatar(
                          imageUrl: u.avatarUrl,
                          radius: 18,
                          fallbackText: u.name,
                        ),
                        title: Text(u.name),
                        onTap: () => Navigator.pop(ctx, u),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (picked == null) {
        _resumeAfterInteractionIfPossible();
        return;
      }
      await _sendToDirect(
        kind: 'share',
        payload: 'Поделился сторис',
        receiverIdOverride: picked.userId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Отправлено: ${picked.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось поделиться сторис: $e')),
      );
    } finally {
      _resumeAfterInteractionIfPossible();
    }
  }

  Future<List<_StoryShareUser>> _loadFollowingUsers() async {
    final myId = widget.currentUserId;
    if (myId == null) return const [];
    final subsRes = await Supabase.instance.client
        .from(SupabaseConstants.followersTable)
        .select('following_id')
        .eq('follower_id', myId)
        .limit(200);
    final followingIds = (subsRes as List<dynamic>)
        .map((e) => (e as Map<String, dynamic>)['following_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (followingIds.isEmpty) return const [];
    final usersRes = await Supabase.instance.client
        .from(SupabaseConstants.usersTable)
        .select('id,name,avatar')
        .inFilter('id', followingIds);
    final users = (usersRes as List<dynamic>)
        .map((e) => e as Map<String, dynamic>)
        .map(
          (j) => _StoryShareUser(
            userId: (j['id'] ?? '').toString(),
            name: ((j['name'] ?? '').toString()).trim().isEmpty
                ? 'Пользователь'
                : (j['name'] as String),
            avatarUrl: (j['avatar'] as String?)?.trim().isEmpty == true
                ? null
                : j['avatar'] as String?,
          ),
        )
        .where((u) => u.userId.isNotEmpty)
        .toList(growable: false);
    users.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return users;
  }

  Future<void> _sendToDirect({
    required String kind,
    required String payload,
    String? receiverIdOverride,
  }) async {
    final senderId = widget.currentUserId;
    if (senderId == null) return;
    final receiverId = receiverIdOverride ?? widget.group.userId;
    if (receiverId.isEmpty || receiverId == senderId) return;
    final previewUrl = _currentStory.imageUrl.isNotEmpty
        ? _currentStory.imageUrl
        : (_currentStory.videoUrl ?? '');
    final structuredText = [
      _storyDmPrefix,
      kind,
      Uri.encodeComponent(_currentStory.id),
      Uri.encodeComponent(previewUrl),
      Uri.encodeComponent(payload),
    ].join('|');
    try {
      await Supabase.instance.client.from(SupabaseConstants.messagesTable).insert({
        'sender_id': senderId,
        'receiver_id': receiverId,
        'text': structuredText,
      });
    } catch (e) {
      // Chat delivery should not block story reaction flow.
    }
  }

  Future<void> _createStoryNotification({
    required String type,
    required String title,
    required String body,
  }) async {
    final actorId = widget.currentUserId;
    if (actorId == null) return;
    final ownerId = _currentStory.userId;
    if (ownerId.isEmpty || ownerId == actorId) return;
    final cleanedBody = body.trim().isEmpty ? title : body.trim();
    final storyTag = '[story:${_currentStory.id}]';
    try {
      await Supabase.instance.client.from(SupabaseConstants.notificationsTable).insert({
        'user_id': ownerId,
        'actor_id': actorId,
        'type': type,
        'title': title,
        'body': '$cleanedBody $storyTag',
        'story_id': _currentStory.id,
      });
    } catch (e) {
      // Notifications should not block story interactions.
    }
  }

  Future<void> _editCaption() async {
    final newCaption = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return _EditCaptionDialog(initialCaption: _currentStory.caption ?? '');
      },
    );
    if (newCaption == null || !mounted) return;
    try {
      await widget.storiesRepository.updateStory(_currentStory.id, caption: newCaption.isEmpty ? null : newCaption);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сохранено')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка')));
    }
  }

  Future<void> _deleteStory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Удалить историю?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true || widget.currentUserId == null || !mounted) return;
    try {
      await widget.storiesRepository.deleteStory(_currentStory.id, widget.currentUserId!);
      if (mounted) widget.onNext();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка удаления')));
    }
  }

  void _openOriginalPost() {
    final postId = _currentStory.originalPostId;
    if (postId == null || postId.isEmpty) return;
    context.push('/post/$postId');
  }

  void _openOriginalAuthorProfile() {
    final authorId = _currentStory.originalPostAuthorId;
    if (authorId == null || authorId.isEmpty) return;
    context.push('/profile/$authorId');
  }

  Widget _instagramReactionBubble(
    String emoji, {
    required double fontSize,
    required double diameter,
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: InkWell(
        onTap: _sendingReply ? null : () => _sendQuickReaction(emoji),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: diameter,
          height: diameter,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: emphasize ? 0.5 : 0.38),
            shape: BoxShape.circle,
            border: Border.all(
              color: emphasize ? Colors.white54 : Colors.white38,
              width: emphasize ? 1.6 : 1.2,
            ),
            boxShadow: emphasize
                ? [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.35),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Text(emoji, style: TextStyle(fontSize: fontSize)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.group.stories.isEmpty) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Нет историй',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    final safeIndex = _currentIndex.clamp(0, widget.group.stories.length - 1);
    if (safeIndex != _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _currentIndex = safeIndex);
        _markCurrentStoryViewed();
        _loadViewsCount();
      });
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: widget.storyController,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.group.stories.length,
          onPageChanged: (i) {
            setState(() => _currentIndex = i);
            _showReplyComposer = false;
            _replyFocusNode.unfocus();
            _markCurrentStoryViewed();
            _loadViewsCount();
          },
          itemBuilder: (context, index) {
            return _StoryContent(
              story: widget.group.stories[index],
              onTapLeft: widget.onPrev,
              onTapRight: widget.onNext,
              onHoldStart: widget.onPause,
              onHoldEnd: widget.onResume,
              isPaused: widget.isPaused,
            );
          },
        ),
        SafeArea(
          child: Column(
            children: [
              _ProgressBars(
                count: widget.group.stories.length,
                currentIndex: _currentIndex,
                duration: _storyBarDuration(),
                paused: widget.isPaused,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    CachedAvatar(
                      imageUrl: widget.group.userAvatarUrl,
                      radius: 18,
                      fallbackText: widget.group.userName,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.group.userName ?? 'Пользователь',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (_isOwnStory)
                      InkWell(
                        onTap: _showViewersSheet,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.remove_red_eye_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _viewsLoading ? '...' : '$_viewsCount',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_isOwnStory)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        color: Colors.white,
                        onSelected: (v) {
                          if (v == 'edit') _editCaption();
                          if (v == 'delete') _deleteStory();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Редактировать', style: TextStyle(color: Colors.black87, fontSize: 16)),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Удалить', style: TextStyle(color: Colors.red, fontSize: 16)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (widget.currentUserId != null && !_isOwnStory)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(left: 12, right: 12, bottom: MediaQuery.of(context).padding.bottom + 12, top: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black54, Colors.transparent]),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_showReplyComposer)
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(24),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(24),
                              onTap: _openComposer,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Text(
                                  'Отправить сообщение...',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: _sendingReply ? null : () => _sendQuickReaction('❤️'),
                          icon: const Icon(Icons.favorite_border_rounded, color: Colors.white),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: _openComposer,
                          icon: const Icon(Icons.mode_comment_outlined, color: Colors.white),
                        ),
                        IconButton(
                          constraints: const BoxConstraints(
                            minWidth: 40,
                            minHeight: 40,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: _shareCurrentStory,
                          icon: const Icon(Icons.send_outlined, color: Colors.white),
                        ),
                      ],
                    ),
                  if (_showReplyComposer) ...[
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 3; i++)
                            _instagramReactionBubble(
                              _quickReactionsRing[i],
                              fontSize: 40,
                              diameter: 64,
                            ),
                          _instagramReactionBubble(
                            '❤️',
                            fontSize: 52,
                            diameter: 86,
                            emphasize: true,
                          ),
                          for (var i = 3; i < _quickReactionsRing.length; i++)
                            _instagramReactionBubble(
                              _quickReactionsRing[i],
                              fontSize: 40,
                              diameter: 64,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            focusNode: _replyFocusNode,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Отправить сообщение...',
                              hintStyle: TextStyle(color: Colors.grey.shade400),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: Colors.white12,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                            onTap: _pauseForInteraction,
                            onSubmitted: (_) => _sendReply(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _sendingReply ? null : _sendReply,
                          icon: _sendingReply
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_currentStory.caption != null && _currentStory.caption!.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: (_currentStory.originalPostId != null &&
                    _currentStory.originalPostId!.isNotEmpty)
                ? (widget.currentUserId != null && !_isOwnStory ? 154 : 112)
                : (widget.currentUserId != null && !_isOwnStory ? 70 : 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _currentStory.caption!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (_currentStory.originalPostId != null &&
            _currentStory.originalPostId!.isNotEmpty)
          Positioned(
            left: 12,
            right: 12,
            bottom: widget.currentUserId != null && !_isOwnStory ? 70 : 24,
            child: InkWell(
              onTap: _openOriginalPost,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 46,
                        height: 62,
                        child: (_currentStory.originalPostPreviewUrl ?? '').isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: _currentStory.originalPostPreviewUrl!,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: Colors.white12,
                                child: const Icon(
                                  Icons.article_outlined,
                                  color: Colors.white70,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Оригинальная публикация',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: _openOriginalAuthorProfile,
                            child: Text(
                              _currentStory.originalPostAuthorName ?? 'Автор',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white70,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Нажмите, чтобы открыть пост',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StoryShareUser {
  const _StoryShareUser({
    required this.userId,
    required this.name,
    required this.avatarUrl,
  });

  final String userId;
  final String name;
  final String? avatarUrl;
}

class _ProgressBars extends StatefulWidget {
  const _ProgressBars({
    required this.count,
    required this.currentIndex,
    required this.duration,
    required this.paused,
  });

  final int count;
  final int currentIndex;
  final Duration duration;
  final bool paused;

  @override
  State<_ProgressBars> createState() => _ProgressBarsState();
}

class _ProgressBarsState extends State<_ProgressBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
  }

  @override
  void didUpdateWidget(_ProgressBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
      _controller.reset();
      _controller.forward();
    }
    if (oldWidget.currentIndex != widget.currentIndex) {
      _controller.reset();
      _controller.forward();
    }
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _controller.stop();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: List.generate(widget.count, (i) {
          final isActive = i == widget.currentIndex;
          final isPast = i < widget.currentIndex;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    if (isPast)
                      Container(color: Colors.white),
                    if (isActive)
                      LayoutBuilder(
                        builder: (context, constraints) {
                          return AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              return SizedBox(
                                width: constraints.maxWidth * _controller.value.clamp(0.0, 1.0),
                                child: Container(color: Colors.white),
                              );
                            },
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Жесты как в Instagram: тап слева — назад, тап справа/по центру — вперёд;
/// удержание пальца — пауза (таймер + видео).
class _StoryContent extends StatelessWidget {
  const _StoryContent({
    required this.story,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.isPaused,
  });

  final StoryEntity story;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final bool isPaused;

  static const double _backZoneFraction = 0.35;

  void _onTapUp(BuildContext context, TapUpDetails details) {
    final w = MediaQuery.sizeOf(context).width;
    final dx = details.localPosition.dx;
    if (dx < w * _backZoneFraction) {
      onTapLeft();
    } else {
      onTapRight();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = story.videoUrl != null && story.videoUrl!.isNotEmpty;
    final musicUrl = story.musicExternalUrl;
    final hasMusicAudio =
        musicUrl != null && musicUrl.trim().isNotEmpty;
    final hasMusicSticker = hasMusicAudio ||
        (story.musicTitle ?? '').trim().isNotEmpty ||
        (story.musicArtist ?? '').trim().isNotEmpty;
    return GestureDetector(
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldEnd,
      onTapUp: (details) => _onTapUp(context, details),
      child: Center(
        child: AspectRatio(
          aspectRatio: _storyAspectRatio,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: hasVideo
                      ? _StoryVideoContent(
                          videoUrl: story.videoUrl!,
                          paused: isPaused,
                          muteVideoForMusicTrack: hasMusicAudio,
                        )
                      : story.imageUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: story.imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (_, progress) => const Center(
                                child:
                                    CircularProgressIndicator(color: Colors.white),
                              ),
                              errorWidget: (_, error, stackTrace) =>
                                  const Center(
                                child: Icon(Icons.broken_image_outlined,
                                    size: 64, color: Colors.white54),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.image_not_supported,
                                  size: 64, color: Colors.white54),
                            ),
                ),
                if (StoryOverlayItem.listFromJson(story.overlaysJson)
                    .isNotEmpty)
                  Positioned.fill(
                    child: StoryOverlaysStack(
                      items:
                          StoryOverlayItem.listFromJson(story.overlaysJson),
                      editable: false,
                    ),
                  ),
                if (hasMusicAudio)
                  _StoryMusicAmbientPlayer(
                    key: ValueKey<String>('${story.id}_music'),
                    audioUrl: musicUrl,
                    paused: isPaused,
                  ),
                if (hasMusicSticker)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 80,
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: StoryMusicSticker(
                          title: (story.musicTitle ?? '').trim().isEmpty
                              ? 'Музыка'
                              : story.musicTitle!.trim(),
                          artist: (story.musicArtist ?? '').trim(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryVideoContent extends StatefulWidget {
  const _StoryVideoContent({
    required this.videoUrl,
    required this.paused,
    this.muteVideoForMusicTrack = false,
  });

  final String videoUrl;
  final bool paused;
  /// Как в Instagram: при стикере «Музыка» звук видео отключается, играет превью трека.
  final bool muteVideoForMusicTrack;

  @override
  State<_StoryVideoContent> createState() => _StoryVideoContentState();
}

class _StoryVideoContentState extends State<_StoryVideoContent> {
  VideoPlayerController? _controller;
  final GlobalVideoAudioState _audioState = GlobalVideoAudioState.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_audioState.ensureLoaded());
    _audioState.isMuted.addListener(_syncVolumeWithGlobalState);
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await _loadVideo(widget.videoUrl);
  }

  Future<void> _loadVideo(String url) async {
    try {
      final c = await createCachedVideoController(url);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.setLooping(true);
      final allowVideoSound =
          !widget.muteVideoForMusicTrack && !_audioState.isMuted.value;
      c.setVolume(allowVideoSound ? 1 : 0);
      _controller = c;
      setState(() {});
      if (!widget.paused) c.play();
    } catch (e) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _audioState.isMuted.removeListener(_syncVolumeWithGlobalState);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  void _syncVolumeWithGlobalState() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final allowVideoSound =
        !widget.muteVideoForMusicTrack && !_audioState.isMuted.value;
    c.setVolume(allowVideoSound ? 1 : 0);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant _StoryVideoContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      unawaited(_controller?.dispose());
      _controller = null;
      setState(() {});
      unawaited(_loadVideo(widget.videoUrl));
      return;
    }
    if (oldWidget.muteVideoForMusicTrack != widget.muteVideoForMusicTrack) {
      _syncVolumeWithGlobalState();
    }
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        c.pause();
      } else {
        c.play();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final size = c.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(c),
                if (!widget.muteVideoForMusicTrack)
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: GestureDetector(
                      onTap: () {
                        unawaited(_audioState.toggle());
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          _audioState.isMuted.value
                              ? Icons.volume_off_rounded
                              : Icons.volume_up_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Фоновое воспроизведение превью трека в сторис (пауза по удержанию как в Instagram).
///
/// Не привязан к [GlobalVideoAudioState]: иначе при дефолтном «mute» трек не слышен.
class _StoryMusicAmbientPlayer extends StatefulWidget {
  const _StoryMusicAmbientPlayer({
    super.key,
    required this.audioUrl,
    required this.paused,
  });

  final String audioUrl;
  final bool paused;

  @override
  State<_StoryMusicAmbientPlayer> createState() =>
      _StoryMusicAmbientPlayerState();
}

class _StoryMusicAmbientPlayerState extends State<_StoryMusicAmbientPlayer> {
  late final AudioPlayer _player;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1);
      await _player.play(UrlSource(widget.audioUrl));
      if (widget.paused) await _player.pause();
    } catch (e) { debugPrint('$e'); }
  }

  Future<void> _applyPause() async {
    if (!mounted) return;
    if (widget.paused) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  @override
  void didUpdateWidget(covariant _StoryMusicAmbientPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.audioUrl != widget.audioUrl) {
      unawaited(_reloadSource());
      return;
    }
    if (oldWidget.paused != widget.paused) {
      unawaited(_applyPause());
    }
  }

  Future<void> _reloadSource() async {
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(UrlSource(widget.audioUrl));
      await _applyPause();
    } catch (e) { debugPrint('$e'); }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _EditCaptionDialog extends StatefulWidget {
  const _EditCaptionDialog({required this.initialCaption});

  final String initialCaption;

  @override
  State<_EditCaptionDialog> createState() => _EditCaptionDialogState();
}

class _EditCaptionDialogState extends State<_EditCaptionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialCaption);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        inputDecorationTheme: InputDecorationTheme(
          fillColor: Colors.grey.shade200,
          filled: true,
          hintStyle: const TextStyle(color: Colors.black38),
        ),
      ),
      child: AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Редактировать подпись', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: _controller,
          cursorColor: Colors.black,
          cursorWidth: 2,
          style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Подпись к истории',
            hintStyle: const TextStyle(color: Colors.black38),
            filled: true,
            fillColor: Colors.grey.shade200,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.black26),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _controller.text.trim()),
            child: const Text('Сохранить', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
