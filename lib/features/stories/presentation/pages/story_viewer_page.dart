import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
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
  static const Duration _storyDuration = Duration(seconds: 5);

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
    _timer?.cancel();
    _timer = Timer(_storyDuration, () {
      if (!mounted) return;
      _goNext();
    });
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
      body: PageView.builder(
        controller: _groupPageController,
        scrollDirection: Axis.vertical,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: widget.groups.length,
        onPageChanged: (i) {
          setState(() => _currentGroupIndex = i);
          _startTimer();
        },
        itemBuilder: (context, groupIndex) {
          final group = widget.groups[groupIndex];
          return _StoryGroupView(
            group: group,
            storyController: _storyPageControllers[groupIndex],
            onNext: _goNext,
            onPrev: _goPrev,
            currentUserId: currentUserId,
            storiesRepository: storiesRepo,
          );
        },
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
    this.currentUserId,
    required this.storiesRepository,
  });

  final StoryGroupEntity group;
  final PageController storyController;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final String? currentUserId;
  final StoriesRepository storiesRepository;

  @override
  State<_StoryGroupView> createState() => _StoryGroupViewState();
}

class _StoryGroupViewState extends State<_StoryGroupView> {
  int _currentIndex = 0;
  final _replyController = TextEditingController();
  bool _sendingReply = false;
  final Set<String> _markedViewedIds = <String>{};
  int _viewsCount = 0;
  bool _viewsLoading = false;

  @override
  void initState() {
    super.initState();
    _markCurrentStoryViewed();
    _loadViewsCount();
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
    _replyController.dispose();
    super.dispose();
  }

  StoryEntity get _currentStory => widget.group.stories[_currentIndex];
  bool get _isOwnStory => widget.currentUserId != null && widget.group.userId == widget.currentUserId;

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
    setState(() => _sendingReply = true);
    try {
      await widget.storiesRepository.addStoryReply(
        storyId: _currentStory.id,
        userId: widget.currentUserId!,
        text: text,
      );
      if (mounted) {
        _replyController.clear();
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
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Future<void> _editCaption() async {
    final newCaption = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: _currentStory.caption ?? '');
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
              controller: c,
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
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, c.text.trim()),
                child: const Text('Сохранить', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
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
            _markCurrentStoryViewed();
            _loadViewsCount();
          },
          itemBuilder: (context, index) {
            return _StoryContent(
              story: widget.group.stories[index],
              onTapLeft: widget.onPrev,
              onTapRight: widget.onNext,
            );
          },
        ),
        SafeArea(
          child: Column(
            children: [
              _ProgressBars(
                count: widget.group.stories.length,
                currentIndex: _currentIndex,
                duration: _StoryViewerPageState._storyDuration,
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Написать сообщение...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        filled: true,
                        fillColor: Colors.white12,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      ),
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

class _ProgressBars extends StatefulWidget {
  const _ProgressBars({
    required this.count,
    required this.currentIndex,
    required this.duration,
  });

  final int count;
  final int currentIndex;
  final Duration duration;

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
  });

  final StoryEntity story;
  final VoidCallback onTapLeft;
  final VoidCallback onTapRight;

  @override
  Widget build(BuildContext context) {
    final hasVideo = story.videoUrl != null && story.videoUrl!.isNotEmpty;
    return GestureDetector(
      onTapDown: (details) {
        final w = MediaQuery.sizeOf(context).width;
        if (details.localPosition.dx < w * 0.4) {
          onTapLeft();
        } else {
          onTapRight();
        }
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: _storyAspectRatio,
          child: ClipRect(
            child: hasVideo
                ? _StoryVideoContent(videoUrl: story.videoUrl!)
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
  const _StoryVideoContent({required this.videoUrl});

  final String videoUrl;

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
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller.value.size.width,
        height: _controller.value.size.height,
        child: VideoPlayer(_controller),
      ),
    );
  }
}
