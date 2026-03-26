import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/story_entity.dart';
import '../../domain/entities/story_group_entity.dart';
import '../../domain/repositories/stories_repository.dart';
import '../../../../core/widgets/cached_avatar.dart';

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
    return hasVideo ? _videoStoryDuration : _photoStoryDuration;
  }

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
      context.pop();
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
      context.pop();
    }
  }

  void _goPrev() {
    if (widget.groups.isEmpty) {
      context.pop();
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
      context.pop();
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
            context.pop();
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
              progressDuration: _durationForStory(groupIndex: groupIndex, storyIndex: 0),
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
    required this.progressDuration,
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
  final Duration progressDuration;
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
  static const List<String> _quickReactions = ['🔥', '😍', '👏', '😂', '😮'];
  static const String _storyDmPrefix = '__story__';
  int _currentIndex = 0;
  final _replyController = TextEditingController();
  final _replyFocusNode = FocusNode();
  bool _sendingReply = false;
  bool _showReplyComposer = false;
  bool _isFastForward = false;
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

  void _togglePauseResume() {
    if (widget.isPaused) {
      widget.onResume();
    } else {
      widget.onPause();
    }
  }

  void _handleRightZoneTap() {
    final hasVideo = (_currentStory.videoUrl ?? '').isNotEmpty;
    if (!hasVideo) {
      widget.onNext();
      return;
    }
    widget.onNext();
  }

  void _startRightHoldFastForward() {
    final hasVideo = (_currentStory.videoUrl ?? '').isNotEmpty;
    if (!hasVideo) {
      return;
    }
    setState(() => _isFastForward = true);
  }

  void _stopRightHoldFastForward() {
    if (!_isFastForward) return;
    setState(() => _isFastForward = false);
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
    } catch (_) {
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
    } catch (_) {
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
    } catch (_) {
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
      await _sendToDirect(kind: 'reply', payload: text);
      if (mounted) {
        _replyController.clear();
        setState(() => _showReplyComposer = false);
        _replyFocusNode.unfocus();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ответ отправлен'), duration: Duration(seconds: 2)),
        );
      }
    } catch (_) {
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
      await _sendToDirect(kind: 'reaction', payload: emoji);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Реакция $emoji отправлена'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
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
    } catch (_) {
      // Chat delivery should not block story reaction flow.
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
    } catch (_) {
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
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка удаления')));
    }
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
            _isFastForward = false;
            _replyFocusNode.unfocus();
            _markCurrentStoryViewed();
            _loadViewsCount();
          },
          itemBuilder: (context, index) {
            return _StoryContent(
              story: widget.group.stories[index],
              onTapLeft: widget.onPrev,
              onTapRight: _handleRightZoneTap,
              onTapCenter: _togglePauseResume,
              onHoldStart: widget.onPause,
              onHoldEnd: widget.onResume,
              onRightHoldStart: _startRightHoldFastForward,
              onRightHoldEnd: _stopRightHoldFastForward,
              isPaused: widget.isPaused,
              isFastForward: _isFastForward,
            );
          },
        ),
        SafeArea(
          child: Column(
            children: [
              _ProgressBars(
                count: widget.group.stories.length,
                currentIndex: _currentIndex,
                duration: widget.progressDuration,
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
                          child: OutlinedButton(
                            onPressed: _openComposer,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white38),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            ),
                            child: const Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Отправить сообщение',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _sendingReply ? null : () => _sendQuickReaction('❤️'),
                          icon: const Icon(Icons.favorite_border_rounded, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: _openComposer,
                          icon: const Icon(Icons.mode_comment_outlined, color: Colors.white),
                        ),
                        IconButton(
                          onPressed: _shareCurrentStory,
                          icon: const Icon(Icons.send_outlined, color: Colors.white),
                        ),
                      ],
                    ),
                  if (_showReplyComposer) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.center,
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 14,
                        runSpacing: 10,
                        children: _quickReactions.map((emoji) {
                          return InkWell(
                            onTap: _sendingReply ? null : () => _sendQuickReaction(emoji),
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Text(
                                emoji,
                                style: const TextStyle(fontSize: 24),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _replyController,
                            focusNode: _replyFocusNode,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Написать сообщение...',
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
            bottom: widget.currentUserId != null && !_isOwnStory ? 70 : 24,
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

class _StoryContent extends StatelessWidget {
  const _StoryContent({
    required this.story,
    required this.onTapLeft,
    required this.onTapRight,
    required this.onTapCenter,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onRightHoldStart,
    required this.onRightHoldEnd,
    required this.isPaused,
    required this.isFastForward,
  });

  final StoryEntity story;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;
  final VoidCallback onTapCenter;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onRightHoldStart;
  final VoidCallback onRightHoldEnd;
  final bool isPaused;
  final bool isFastForward;

  @override
  Widget build(BuildContext context) {
    final hasVideo = story.videoUrl != null && story.videoUrl!.isNotEmpty;
    return GestureDetector(
      onLongPressStart: (details) {
        final w = MediaQuery.sizeOf(context).width;
        final dx = details.localPosition.dx;
        final isRightZone = dx > w * 0.85;
        if (isRightZone && hasVideo) {
          onRightHoldStart();
          return;
        }
        onHoldStart();
      },
      onLongPressEnd: (details) {
        final w = MediaQuery.sizeOf(context).width;
        final dx = details.localPosition.dx;
        final isRightZone = dx > w * 0.85;
        if (isRightZone && hasVideo) {
          onRightHoldEnd();
          return;
        }
        onHoldEnd();
      },
      onLongPressCancel: () {
        onRightHoldEnd();
        onHoldEnd();
      },
      onTapDown: (details) {
        if (hasVideo) {
          onTapCenter();
          return;
        }
        final w = MediaQuery.sizeOf(context).width;
        final dx = details.localPosition.dx;
        if (dx < w * 0.15) {
          onTapLeft();
        } else if (dx > w * 0.85) {
          onTapRight();
        } else {
          onTapCenter();
        }
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: _storyAspectRatio,
          child: ClipRect(
            child: hasVideo
                ? _StoryVideoContent(
                    videoUrl: story.videoUrl!,
                    paused: isPaused,
                    fastForward: isFastForward,
                  )
                : story.imageUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: story.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (_, progress) => const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                        errorWidget: (_, error, stackTrace) => const Center(
                          child: Icon(Icons.broken_image_outlined,
                              size: 64, color: Colors.white54),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.image_not_supported,
                            size: 64, color: Colors.white54),
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
    required this.fastForward,
  });

  final String videoUrl;
  final bool paused;
  final bool fastForward;

  @override
  State<_StoryVideoContent> createState() => _StoryVideoContentState();
}

class _StoryVideoContentState extends State<_StoryVideoContent> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.setLooping(true);
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _StoryVideoContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_controller.value.isInitialized) return;
    if (oldWidget.paused != widget.paused) {
      if (widget.paused) {
        _controller.pause();
      } else {
        _controller.play();
      }
    }
    if (oldWidget.fastForward != widget.fastForward) {
      _controller.setPlaybackSpeed(widget.fastForward ? 2.0 : 1.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final size = _controller.value.size;
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
                VideoPlayer(_controller),
                if (widget.fastForward)
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Text(
                            '2x',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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
