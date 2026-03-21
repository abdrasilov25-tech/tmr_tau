import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:video_player/video_player.dart';

import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../chat/presentation/widgets/chat_stories_friends_strip.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../../../notifications/domain/repositories/notifications_repository.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';

/// Экран «Главное» — лента публикаций в стиле TikTok: вкладки
/// **Рекомендации** и **Подписки** (без своих постов — они в профиле).
///
/// Подключение:
/// - Для показа медиа используются поля `imageUrl/videoUrl` у `PostEntity`.
/// - Лайки/репосты вызывают `PostRepository.toggleLike/toggleRepost`.
/// - Комментарии открывают `PostDetailPage` по маршруту `/post/:id`.
/// - Репост в требованиях заменён на реальные "repost" из базы (`toggleRepost`).
/// - Share: открывает список пользователей, затем отправляет в чат с выбранным.
class MainHomePage extends StatefulWidget {
  const MainHomePage({super.key});

  @override
  State<MainHomePage> createState() => _MainHomePageState();
}

enum _FeedTab {
  /// «Для вас» — не от себя и не от подписок; персональный скор (лайки/сохранения/просмотры/хэштеги).
  recommendations,
  /// Только авторы из подписок.
  subscriptions,
}

class _MainHomePageState extends State<MainHomePage> {
  static const int _pageSize = 10;

  final _scrollController = ScrollController();

  /// Высота одной карточки ленты (для расчёта видимого индекса и просмотров).
  double? _feedItemHeight;
  String? _impressionActivePostId;
  Timer? _impressionTimer;

  bool _initialLoading = true;
  bool _isLoadingMore = false;
  bool _storiesLoading = true;
  bool _storyRetryScheduled = false;

  _FeedTab _feedTab = _FeedTab.recommendations;

  final List<PostEntity> _postsRecommendations = [];
  final List<PostEntity> _postsSubscriptions = [];

  int _cursorRecommendations = 0;
  int _cursorSubscriptions = 0;

  bool _hasMoreRecommendations = true;
  bool _hasMoreSubscriptions = true;

  /// Текущая видимая лента (по выбранной вкладке).
  List<PostEntity> get _posts => _feedTab == _FeedTab.recommendations
      ? _postsRecommendations
      : _postsSubscriptions;

  bool get _hasMore => _feedTab == _FeedTab.recommendations
      ? _hasMoreRecommendations
      : _hasMoreSubscriptions;
  List<StoryGroupEntity> _storyGroups = const [];
  Map<String, bool> _newStoriesByUserId = const {};

  String? _currentUserId;
  String? _loadedUserId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Текущий userId берём из AuthBloc (в проекте так принято).
    final authState = context.read<AuthBloc>().state;
    _currentUserId = authState is AuthAuthenticated ? authState.user.id : null;

    debugPrint('[MainHomePage] opened (currentUserId=${_currentUserId ?? 'null'})');
    _loadInitial();
    _loadStories();
  }

  @override
  void dispose() {
    _cancelImpressionTimer();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _ensureImpressionTimer() {
    if (_impressionTimer != null) return;
    if (_currentUserId == null) return;
    _impressionTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _pulseFeedImpression(),
    );
  }

  void _cancelImpressionTimer() {
    _impressionTimer?.cancel();
    _impressionTimer = null;
    _impressionActivePostId = null;
  }

  void _pulseFeedImpression() {
    if (!mounted) return;
    if (_feedTab != _FeedTab.recommendations) return;
    final postId = _impressionActivePostId;
    if (postId == null) return;
    unawaited(
      context.read<PostRepository>().recordPublicationFeedImpression(
            postId: postId,
            watchedMsDelta: 4000,
          ),
    );
  }

  void _syncVisiblePostForImpression() {
    if (_feedTab != _FeedTab.recommendations) return;
    final h = _feedItemHeight;
    if (h == null || h <= 0) return;
    if (_postsRecommendations.isEmpty) return;
    if (!_scrollController.hasClients) return;
    final idx = (_scrollController.offset / h)
        .floor()
        .clamp(0, _postsRecommendations.length - 1);
    final post = _postsRecommendations[idx];
    if (post.id != _impressionActivePostId) {
      _impressionActivePostId = post.id;
    }
  }

  void _onScroll() {
    if (!_hasMore) return;
    if (_isLoadingMore) return;
    if (!_scrollController.hasClients) return;

    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    if (max - current <= 450) {
      _loadMore();
    }
    _syncVisiblePostForImpression();
  }

  Future<void> _loadInitial() async {
    final authState = context.read<AuthBloc>().state;
    final activeUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    _currentUserId = activeUserId;
    _loadedUserId = _currentUserId;
    _feedTab = _FeedTab.recommendations;
    setState(() => _initialLoading = true);
    _postsRecommendations.clear();
    _postsSubscriptions.clear();
    _cursorRecommendations = 0;
    _cursorSubscriptions = 0;
    _hasMoreRecommendations = true;
    _hasMoreSubscriptions = true;
    try {
      await _fetchPageForTab(_feedTab, reset: true);
      if (!mounted) return;
      setState(() => _initialLoading = false);
      debugPrint(
        '[MainHomePage] loaded tab=$_feedTab count=${_posts.length}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        if (_feedTab == _FeedTab.recommendations) {
          _hasMoreRecommendations = false;
        } else {
          _hasMoreSubscriptions = false;
        }
      });
    }
  }

  Future<void> _fetchPageForTab(_FeedTab tab, {required bool reset}) async {
    final repo = context.read<PostRepository>();
    final followingIds = await _loadFollowingUserIds();

    if (tab == _FeedTab.recommendations) {
      if (reset) {
        _cursorRecommendations = 0;
      }
      final page = await repo.getPublicationsFeedRecommendations(
        currentUserId: _currentUserId,
        followingUserIds: followingIds,
        limit: _pageSize,
        discoveryDbOffset: _cursorRecommendations,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _postsRecommendations
            ..clear()
            ..addAll(page.posts);
        } else {
          final existingIds = _postsRecommendations.map((p) => p.id).toSet();
          for (final p in page.posts) {
            if (existingIds.add(p.id)) {
              _postsRecommendations.add(p);
            }
          }
        }
        _cursorRecommendations = page.nextOffset;
        _hasMoreRecommendations =
            page.posts.isNotEmpty && page.posts.length >= _pageSize;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_feedTab != _FeedTab.recommendations) return;
        _syncVisiblePostForImpression();
        _ensureImpressionTimer();
      });
      return;
    }

    // Подписки
    if (reset) {
      _cursorSubscriptions = 0;
    }
    final page = await repo.getPublicationsFeedSubscriptions(
      currentUserId: _currentUserId,
      followingUserIds: followingIds,
      limit: _pageSize,
      offset: _cursorSubscriptions,
    );
    if (!mounted) return;
    setState(() {
      if (reset) {
        _postsSubscriptions
          ..clear()
          ..addAll(page.posts);
      } else {
        final existingIds = _postsSubscriptions.map((p) => p.id).toSet();
        for (final p in page.posts) {
          if (existingIds.add(p.id)) {
            _postsSubscriptions.add(p);
          }
        }
      }
      _cursorSubscriptions = page.nextOffset;
      _hasMoreSubscriptions =
          page.posts.isNotEmpty && page.posts.length >= _pageSize;
    });
  }

  void _onFeedTabChanged(_FeedTab tab) {
    if (_feedTab == tab) return;
    if (tab == _FeedTab.subscriptions) {
      _cancelImpressionTimer();
    }
    setState(() => _feedTab = tab);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    if (tab == _FeedTab.recommendations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncVisiblePostForImpression();
        _ensureImpressionTimer();
      });
    }
    final tabEmpty = tab == _FeedTab.recommendations
        ? _postsRecommendations.isEmpty
        : _postsSubscriptions.isEmpty;
    if (tabEmpty) {
      unawaited(_fetchPageForTab(tab, reset: true));
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      await _fetchPageForTab(_feedTab, reset: false);
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadStories() async {
    setState(() => _storiesLoading = true);
    try {
      final storiesRepo = context.read<StoriesRepository>();
      final allGroups = (await storiesRepo.getStoriesGroupedByUser())
          .where((g) => g.stories.isNotEmpty)
          .toList(growable: false);
      final groups = await _filterStoriesByFollowing(allGroups);
      final viewedStoryIds = _currentUserId == null
          ? const <String>{}
          : await storiesRepo.getViewedStoryIds(_currentUserId!);
      final nextMap = <String, bool>{};
      for (final g in groups) {
        nextMap[g.userId] = g.stories.any((s) => !viewedStoryIds.contains(s.id));
      }
      if (!mounted) return;
      setState(() {
        _storyGroups = groups;
        _newStoriesByUserId = nextMap;
        _storiesLoading = false;
        _storyRetryScheduled = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Не очищаем уже загруженные сторис при временной ошибке,
        // чтобы блок сторис в ленте не становился пустым.
        _storiesLoading = false;
      });
    }
  }

  Future<List<String>> _loadFollowingUserIds() async {
    final uid = _currentUserId;
    if (uid == null) return const [];
    try {
      final profiles =
          await context.read<ProfileRepository>().getFollowingUsers(uid);
      return profiles.map((p) => p.id).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<StoryGroupEntity>> _filterStoriesByFollowing(
    List<StoryGroupEntity> groups,
  ) async {
    final uid = _currentUserId;
    if (uid == null || groups.isEmpty) return groups;
    try {
      final following = await context.read<ProfileRepository>().getFollowingUsers(uid);
      final followingIds = following.map((u) => u.id).toSet();
      return groups
          .where((g) => g.userId == uid || followingIds.contains(g.userId))
          .toList(growable: false);
    } catch (_) {
      return groups;
    }
  }

  Future<void> _openAddStoryAndRefresh() async {
    await context.push('/add-story');
    if (!mounted) return;
    await _loadStories();
  }

  Future<void> _refreshPost(String postId) async {
    if (_currentUserId == null) return;
    final repo = context.read<PostRepository>();
    final updated = await repo.getPostById(postId, currentUserId: _currentUserId);
    if (!mounted) return;
    if (updated == null) return;

    setState(() {
      var i = _postsRecommendations.indexWhere((p) => p.id == postId);
      if (i != -1) {
        _postsRecommendations[i] = updated;
      }
      i = _postsSubscriptions.indexWhere((p) => p.id == postId);
      if (i != -1) {
        _postsSubscriptions[i] = updated;
      }
    });
  }

  Future<void> _toggleLike(PostEntity post) async {
    final userId = _currentUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы ставить лайки')),
      );
      return;
    }

    // Оптимистичное обновление UI.
    final isNowLiked = !post.isLikedByMe;
    setState(() {
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i == -1) return;
      final next = post.copyWith(
        isLikedByMe: isNowLiked,
        likesCount: (post.likesCount + (isNowLiked ? 1 : -1)).clamp(0, 1 << 31),
      );
      _posts[i] = next;
    });

    // TODO: при необходимости можно заменить на запрос с обновлением из БД.
    try {
      await context.read<PostRepository>().toggleLike(post.id, userId);
      await _refreshPost(post.id);
    } catch (_) {
      await _refreshPost(post.id);
    }
  }

  Future<void> _toggleRepost(PostEntity post) async {
    final userId = _currentUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы репостить')),
      );
      return;
    }

    final isNowReposted = !post.isRepostedByMe;
    setState(() {
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i == -1) return;
      final next = post.copyWith(
        isRepostedByMe: isNowReposted,
        repostsCount: (post.repostsCount + (isNowReposted ? 1 : -1)).clamp(0, 1 << 31),
      );
      _posts[i] = next;
    });

    try {
      await context.read<PostRepository>().toggleRepost(post.id, userId);
      await _refreshPost(post.id);
    } catch (_) {
      await _refreshPost(post.id);
    }
  }

  Future<void> _toggleSave(PostEntity post) async {
    final userId = _currentUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы сохранять публикации')),
      );
      return;
    }

    final isNowSaved = !post.isSavedByMe;
    setState(() {
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i == -1) return;
      _posts[i] = post.copyWith(isSavedByMe: isNowSaved);
    });
    try {
      await context.read<PostRepository>().toggleSave(post.id, userId);
      await _refreshPost(post.id);
    } catch (_) {
      await _refreshPost(post.id);
    }
  }

  Future<void> _shareToUser(PostEntity post) async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы поделиться')),
      );
      return;
    }

    final pickedUser = await showModalBottomSheet<_UserRow>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => _ShareToUserSheet(
        currentUserId: _currentUserId!,
      ),
    );

    if (pickedUser == null) return;
    // Открываем чат.
    if (!mounted) return;

    // Реальная отправка сообщения в чат (так же, как это делает `ChatPage`).
    // TODO: Чтобы это было «правильным» шеринговым типом, лучше хранить post_id отдельным полем.
    final senderId = _currentUserId!;
    final receiverId = pickedUser.userId;
    debugPrint('[MainHomePage] share post=${post.id} to user=$receiverId');
    final caption = post.caption.trim();
    final shareText = caption.isNotEmpty
        ? 'Публикация: ${post.id}\n$caption'
        : 'Публикация: ${post.id}';
    try {
      await supa.Supabase.instance.client
          .from(SupabaseConstants.messagesTable)
          .insert({
        'sender_id': senderId,
        'receiver_id': receiverId,
        'text': shareText,
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось отправить сообщение')),
      );
      return;
    }
    if (!mounted) return;
    context.push(
      '/chat/${pickedUser.userId}?name=${Uri.encodeComponent(pickedUser.name)}',
    );
  }

  void _showQuickCreateMenu() {
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы создавать публикации')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Создать',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.person_outline_rounded),
              title: const Text('Прувнуть в ленту'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final created =
                    await context.push<PostEntity>('/add-publication');
                if (created == null || !mounted) return;
                final isPublication =
                    created.kind.trim().toLowerCase() != 'news';
                if (!isPublication) return;
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Сторис'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _openAddStoryAndRefresh();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Видео'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await context.push<PostEntity>(
                  '/add-publication?video=1',
                );
                if (!mounted) return;
              },
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Новость'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/add-news');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    final authState = context.read<AuthBloc>().state;
    final activeUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    if (activeUserId != _loadedUserId && !_initialLoading) {
      _currentUserId = activeUserId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadInitial();
        _loadStories();
      });
    }
    if (!_storiesLoading && _storyGroups.isEmpty && !_storyRetryScheduled) {
      _storyRetryScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadStories();
      });
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded),
          onPressed: _showQuickCreateMenu,
        ),
        title: const Text('tmr_tau', style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          _FeedNotificationsButton(),
          const SizedBox(width: 6),
        ],
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthAuthenticated &&
            (prev is! AuthAuthenticated ||
                prev.user.id != curr.user.id),
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            _currentUserId = state.user.id;
            _loadInitial();
            _loadStories();
          }
        },
        child: _initialLoading
            ? const Center(child: AppLoading())
            : Column(
                children: [
                  _storiesLoading
                      ? const SizedBox(
                          height: 102,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : ChatStoriesFriendsStrip(
                          groups: _storyGroups,
                          newStoriesByUserId: _newStoriesByUserId,
                          currentUserId: _currentUserId,
                          onAddStoryTap: _openAddStoryAndRefresh,
                          onStoryTap: (group) async {
                            if (group.stories.isEmpty) return;
                            await context.push(
                              '/stories',
                              extra: StoryViewerArgs(
                                groups: [group],
                                initialGroupIndex: 0,
                              ),
                            );
                            if (!mounted) return;
                            await _loadStories();
                          },
                        ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: SegmentedButton<_FeedTab>(
                      segments: const [
                        ButtonSegment(
                          value: _FeedTab.recommendations,
                          label: Text('Рекомендации'),
                        ),
                        ButtonSegment(
                          value: _FeedTab.subscriptions,
                          label: Text('Подписки'),
                        ),
                      ],
                      selected: {_feedTab},
                      onSelectionChanged: (Set<_FeedTab> selection) {
                        if (selection.isEmpty) return;
                        _onFeedTabChanged(selection.first);
                      },
                      emptySelectionAllowed: false,
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final itemHeight = constraints.maxHeight.isFinite &&
                                constraints.maxHeight > 0
                            ? constraints.maxHeight
                            : h;
                        _feedItemHeight = itemHeight;

                        if (_posts.isEmpty) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _feedTab == _FeedTab.subscriptions
                                    ? (_currentUserId == null
                                        ? 'Войдите, чтобы видеть публикации подписок.'
                                        : 'Нет публикаций от подписок. Подпишитесь на авторов или откройте вкладку «Рекомендации».')
                                    : 'Пока нет публикаций в рекомендациях.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          );
                        }

                        return ListView.builder(
                          key: ValueKey(_feedTab),
                          controller: _scrollController,
                          padding: EdgeInsets.zero,
                          itemExtent: itemHeight,
                          itemCount: _posts.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= _posts.length) {
                              return SizedBox(
                                height: itemHeight,
                                child: const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              );
                            }

                            final post = _posts[index];
                            return _InstagramPostItem(
                              height: itemHeight,
                              post: post,
                              currentUserId: _currentUserId,
                              onLike: () => _toggleLike(post),
                              onRepost: () => _toggleRepost(post),
                              onSave: () => _toggleSave(post),
                              onComment: () async {
                                await context.push('/post/${post.id}', extra: post);
                                await _refreshPost(post.id);
                              },
                              onShare: () => _shareToUser(post),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _FeedNotificationsButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) {
      return IconButton(
        icon: const Icon(Icons.favorite_border_rounded),
        onPressed: () => context.push('/notifications'),
      );
    }

    return FutureBuilder<int>(
      future: context.read<NotificationsRepository>().getUnreadCount(userId),
      builder: (context, snapshot) {
        final unread = snapshot.data ?? 0;
        return IconButton(
          onPressed: () => context.push('/notifications'),
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.favorite_border_rounded),
              if (unread > 0)
                Positioned(
                  right: -1,
                  top: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InstagramPostItem extends StatefulWidget {
  const _InstagramPostItem({
    required this.height,
    required this.post,
    required this.currentUserId,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onSave,
    required this.onShare,
  });

  final double height;
  final PostEntity post;
  final String? currentUserId;

  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onSave;
  final VoidCallback onShare;

  @override
  State<_InstagramPostItem> createState() => _InstagramPostItemState();
}

class _InstagramPostItemState extends State<_InstagramPostItem> {
  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final mediaHeight = widget.height;

    return SizedBox(
      height: mediaHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: _PostMedia(
              imageUrl: p.imageUrl,
              videoUrl: p.videoUrl,
            ),
          ),
          // Верхняя панель: автор.
          Positioned(
            left: 12,
            right: 12,
            top: 10,
            child: SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CachedAvatar(
                    imageUrl: p.userAvatarUrl?.isNotEmpty == true
                        ? '${p.userAvatarUrl}?uid=${p.userId}'
                        : null,
                    radius: 18,
                    fallbackText: p.userName ?? 'П',
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      p.userName ?? 'Пользователь',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Низ: описание + действия.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Описание поверх медиа (как в IG).
                  if ((p.caption).trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p.caption.trim(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                    ),
                    child: Row(
                      children: [
                        _ActionButton(
                          icon: p.isLikedByMe ? Icons.favorite : Icons.favorite_border,
                          iconColor: p.isLikedByMe ? Colors.redAccent : Colors.white,
                          label: 'Лайк',
                          count: p.likesCount,
                          onTap: widget.onLike,
                        ),
                        _ActionButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          iconColor: Colors.white,
                          label: 'Коммент',
                          count: p.commentsCount,
                          onTap: widget.onComment,
                        ),
                        _ActionButton(
                          icon: p.isRepostedByMe ? Icons.repeat : Icons.repeat_outlined,
                          iconColor: p.isRepostedByMe ? Colors.cyanAccent : Colors.white,
                          label: 'Репост',
                          count: p.repostsCount,
                          onTap: widget.onRepost,
                        ),
                        _SaveButton(
                          onTap: widget.onSave,
                          isSaved: p.isSavedByMe,
                        ),
                        const SizedBox(width: 2),
                        _ShareButton(
                          onTap: widget.onShare,
                          label: 'Поделиться',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostMedia extends StatelessWidget {
  const _PostMedia({
    required this.imageUrl,
    required this.videoUrl,
  });

  final String imageUrl;
  final String? videoUrl;

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => _MediaPlaceholder(type: _MediaPlaceholderType.photo),
      );
    }

    if (videoUrl != null && videoUrl!.isNotEmpty) {
      return _VideoMedia(videoUrl: videoUrl!);
    }

    return _MediaPlaceholder(type: _MediaPlaceholderType.neutral);
  }
}

enum _MediaPlaceholderType { neutral, photo }

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.type});

  final _MediaPlaceholderType type;

  @override
  Widget build(BuildContext context) {
    final text = type == _MediaPlaceholderType.photo ? 'Фото-заглушка' : 'Медиа-заглушка';
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, color: Colors.white.withValues(alpha: 0.7), size: 56),
            const SizedBox(height: 10),
            Text(
              text,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoMedia extends StatefulWidget {
  const _VideoMedia({required this.videoUrl});

  final String videoUrl;

  @override
  State<_VideoMedia> createState() => _VideoMediaState();
}

class _VideoMediaState extends State<_VideoMedia> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..setLooping(true)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: VideoPlayer(_controller),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: SizedBox(
          width: 70,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 24),
              const SizedBox(height: 4),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onTap, required this.isSaved});

  final VoidCallback onTap;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: SizedBox(
          width: 54,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: Colors.white,
                size: 25,
              ),
              const SizedBox(height: 4),
              const Text(
                'Сохран.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.onTap, required this.label});

  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: SizedBox(
          width: 70,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send_outlined, color: Colors.white, size: 26),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MediaType { text, photo, video }

class _CreatePostResult {
  const _CreatePostResult({required this.caption, required this.media});

  final String caption;
  final _MediaType media;
}

class _CreatePostSheet extends StatefulWidget {
  const _CreatePostSheet({
    required this.placeholderPhotoUrl,
    required this.placeholderVideoUrl,
  });

  final String placeholderPhotoUrl;
  final String placeholderVideoUrl;

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _captionController = TextEditingController();
  _MediaType _media = _MediaType.text;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'Создать публикацию',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _captionController,
            maxLines: 4,
            minLines: 1,
            decoration: const InputDecoration(
              hintText: 'Текст публикации...',
              hintStyle: TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Color(0xFF111827),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 14),

          const Text(
            'Медиа (заглушка)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),

          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MediaChip(
                selected: _media == _MediaType.text,
                label: 'Только текст',
                onTap: () => setState(() => _media = _MediaType.text),
              ),
              _MediaChip(
                selected: _media == _MediaType.photo,
                label: 'Фото (заглушка)',
                onTap: () => setState(() => _media = _MediaType.photo),
              ),
              _MediaChip(
                selected: _media == _MediaType.video,
                label: 'Видео (заглушка)',
                onTap: () => setState(() => _media = _MediaType.video),
              ),
            ],
          ),

          const SizedBox(height: 14),
          _PreviewPlaceholder(
            media: _media,
            photoUrl: widget.placeholderPhotoUrl,
            videoUrl: widget.placeholderVideoUrl,
          ),

          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              final caption = _captionController.text.trim();
              if (caption.isEmpty && _media == _MediaType.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Введите текст публикации')),
                );
                return;
              }

              Navigator.of(context).pop(
                _CreatePostResult(
                  caption: caption,
                  media: _media,
                ),
              );
            },
            child: const Text('Опубликовать'),
          ),
        ],
      ),
    );
  }
}

class _MediaChip extends StatelessWidget {
  const _MediaChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      label: Text(label),
      onSelected: (_) => onTap(),
      selectedColor: Colors.white.withValues(alpha: 0.12),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      labelStyle: const TextStyle(color: Colors.white),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({
    required this.media,
    required this.photoUrl,
    required this.videoUrl,
  });

  final _MediaType media;
  final String photoUrl;
  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    if (media == _MediaType.photo) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              const SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
          errorWidget: (context, url, error) =>
              Container(height: 180, color: Colors.white.withValues(alpha: 0.06), child: const Icon(Icons.image_not_supported_outlined)),
        ),
      );
    }

    if (media == _MediaType.video) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white.withValues(alpha: 0.06),
        ),
        child: const Center(
          child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 54),
        ),
      );
    }

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        color: Colors.transparent,
      ),
      child: const Center(
        child: Text(
          'Медиа не выбрано',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _UserRow {
  const _UserRow({required this.userId, required this.name, this.avatarUrl});

  final String userId;
  final String name;
  final String? avatarUrl;
}

class _ShareToUserSheet extends StatefulWidget {
  const _ShareToUserSheet({required this.currentUserId});

  final String currentUserId;

  @override
  State<_ShareToUserSheet> createState() => _ShareToUserSheetState();
}

class _ShareToUserSheetState extends State<_ShareToUserSheet> {
  final _searchController = TextEditingController();
  bool _loading = false;
  String? _error;

  List<_UserRow> _users = [];

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load(''); // initial
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = supa.Supabase.instance.client;
      final trimmed = q.trim();
      final res = trimmed.isNotEmpty
          ? await client
              .from('users')
              .select('id,name,avatar')
              .neq('id', widget.currentUserId)
              .ilike('name', '%$trimmed%')
              .limit(20)
          : await client
              .from('users')
              .select('id,name,avatar')
              .neq('id', widget.currentUserId)
              .limit(20);

      final list = res as List<dynamic>;
      final mapped = list.map((e) {
        final m = e as Map<String, dynamic>;
        return _UserRow(
          userId: m['id'] as String,
          name: (m['name'] as String?) ?? 'Пользователь',
          avatarUrl: m['avatar'] as String?,
        );
      }).toList(growable: false);

      if (!mounted) return;
      setState(() {
        _users = mapped;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Поделиться с другом',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              )
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => _load(v));
            },
            decoration: InputDecoration(
              hintText: 'Поиск по имени...',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF111827),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
            ),
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Ошибка: $_error',
                style: const TextStyle(color: Colors.redAccent),
              ),
            )
          else if (_users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Никто не найден',
                style: TextStyle(color: Colors.white70),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _users.length,
                separatorBuilder: (_, _) => const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final u = _users[index];
                  return ListTile(
                    leading: CachedAvatar(
                      imageUrl: u.avatarUrl?.isNotEmpty == true ? u.avatarUrl : null,
                      radius: 20,
                      fallbackText: u.name,
                    ),
                    title: Text(
                      u.name,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white60),
                    onTap: () => Navigator.of(context).pop(u),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

