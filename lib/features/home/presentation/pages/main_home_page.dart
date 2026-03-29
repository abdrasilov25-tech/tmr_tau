import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:video_player/video_player.dart';

import '../../../../core/media/cached_video_controller.dart';
import '../../../../core/utils/notification_badge_format.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/double_tap_like_burst.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../chat/presentation/widgets/chat_stories_friends_strip.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../../../notifications/domain/repositories/notifications_repository.dart';
import '../../../notifications/presentation/notification_activity_peek_bus.dart';
import '../../../notifications/presentation/widgets/notification_activity_peek_bar.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../post/presentation/widgets/post_photo_gallery.dart';
import '../widgets/user_avatar_tap.dart';

/// Экран «Главное» — лента публикаций в стиле TikTok: вкладки
/// **Рекомендации** и **Подписки** — отдельные вертикальные ленты (свайп вверх/вниз),
/// у каждой вкладки свой [PageController], контент не смешивается.
///
/// Подключение:
/// - Для показа медиа используются поля `imageUrl/videoUrl` у `PostEntity`.
/// - Лайки/репосты вызывают `PostRepository.toggleLike/toggleRepost`.
/// - Комментарии открывают `PostDetailPage` по маршруту `/post/:id`.
/// - Репост в требованиях заменён на реальные "repost" из базы (`toggleRepost`).
/// - Share: открывает список пользователей, затем отправляет в чат с выбранным.
/// - Precache: первые карточки ленты, соседние при скролле (фото+аватар), превью сторис.
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
  /// Дольше, чем раньше: при возврате на вкладку «Публикации» не сбрасываем ленту.
  static const Duration _warmCacheTtl = Duration(minutes: 45);
  static _MainHomeWarmCache? _warmCache;

  /// Отдельный вертикальный «экран» на вкладку — свайп как в TikTok.
  late final PageController _pageRecommendationsController;
  late final PageController _pageSubscriptionsController;

  /// Индекс текущей «карточки» в вертикальной ленте (отдельно для каждой вкладки).
  int _pageIndexRecommendations = 0;
  int _pageIndexSubscriptions = 0;

  int get _activeFeedPageIndex => _feedTab == _FeedTab.recommendations
      ? _pageIndexRecommendations
      : _pageIndexSubscriptions;

  /// Высота одной карточки ленты (viewport [PageView]).
  double? _feedItemHeight;
  String? _impressionActivePostId;
  Timer? _impressionTimer;

  bool _initialLoading = true;
  bool _isLoadingMore = false;
  bool _isFetchingRecommendations = false;
  bool _isFetchingSubscriptions = false;
  DateTime? _lastLoadMoreAt;

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
  Map<String, String> _storyNotesByUserId = const {};

  String? _currentUserId;

  /// Подписок больше не запрашиваем на каждый chunk ленты и второй раз для сторис — один запрос на сессию / после сброса.
  List<String>? _followingIdsCache;
  String? _followingIdsCacheUserId;
  Future<List<String>>? _followingIdsLoadFuture;

  /// Последний индекс, для которого уже вызывали precache соседей (избегаем лишней работы при скролле).
  int? _lastPrecachedFeedIndex;

  @override
  void initState() {
    super.initState();
    _pageRecommendationsController = PageController();
    _pageSubscriptionsController = PageController();

    // Текущий userId берём из AuthBloc (в проекте так принято).
    final authState = context.read<AuthBloc>().state;
    _currentUserId = authState is AuthAuthenticated ? authState.user.id : null;

    debugPrint('[MainHomePage] opened (currentUserId=${_currentUserId ?? 'null'})');
    final cache = _warmCache;
    final canUseCache = cache != null &&
        cache.userId == _currentUserId &&
        DateTime.now().difference(cache.createdAt) <= _warmCacheTtl;
    if (canUseCache) {
      _applyWarmCache(cache);
    }
    // Defer heavy network calls until after first frame to improve perceived startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_runInitialHomeLoad(showLoading: !canUseCache));
    });
  }

  /// Сначала лента, потом сторис — иначе [_storeWarmCache] из параллельного [_loadStories]
  /// может сохранить кэш со списками ещё от прошлого пользователя.
  Future<void> _runInitialHomeLoad({required bool showLoading}) async {
    if (showLoading) {
      await _loadInitial(showLoading: true);
      if (!mounted) return;
      await _loadStories();
    } else {
      // Уже показали кэш — не очищаем списки через _loadInitial (иначе лишний «пустой» экран и двойной запрос).
      await _silentRefreshHome();
    }
  }

  /// Фоновое обновление лент и сторис без сброса уже показанных данных.
  Future<void> _silentRefreshHome() async {
    if (!mounted) return;
    await Future.wait<void>([
      _silentRefreshFeeds(),
      _loadStories(),
    ]);
  }

  Future<void> _silentRefreshFeeds() async {
    try {
      final repo = context.read<PostRepository>();
      final followingIds = await _getFollowingUserIdsCached();
      final rec = await repo.getPublicationsFeedRecommendations(
        currentUserId: _currentUserId,
        followingUserIds: followingIds,
        limit: _pageSize,
        discoveryDbOffset: 0,
      );
      final sub = await repo.getPublicationsFeedSubscriptions(
        currentUserId: _currentUserId,
        followingUserIds: followingIds,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _postsRecommendations
          ..clear()
          ..addAll(rec.posts);
        _cursorRecommendations = rec.nextOffset;
        _hasMoreRecommendations =
            rec.posts.isNotEmpty && rec.posts.length >= _pageSize;
        _postsSubscriptions
          ..clear()
          ..addAll(sub.posts);
        _cursorSubscriptions = sub.nextOffset;
        _hasMoreSubscriptions =
            sub.posts.isNotEmpty && sub.posts.length >= _pageSize;
      });
      _storeWarmCache();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _precacheFeedHead(_postsRecommendations);
        _precacheFeedHead(_postsSubscriptions);
        _lastPrecachedFeedIndex = null;
        _precacheNeighborsForCurrentFeedPost();
      });
    } catch (_) {
      // Оставляем последний успешный кэш на экране.
    }
  }

  /// Смена аккаунта: сбрасываем общий warm-cache и перезагружаем данные.
  Future<void> _reloadHomeAfterAuthUserChange() async {
    _warmCache = null;
    _invalidateFollowingIdsCache();
    _cancelImpressionTimer();
    await _loadInitial(showLoading: true);
    if (!mounted) return;
    await _loadStories();
  }

  @override
  void dispose() {
    _cancelImpressionTimer();
    _pageRecommendationsController.dispose();
    _pageSubscriptionsController.dispose();
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
    if (_postsRecommendations.isEmpty) return;
    final idx = _pageIndexRecommendations.clamp(
      0,
      _postsRecommendations.length - 1,
    );
    final post = _postsRecommendations[idx];
    if (post.id != _impressionActivePostId) {
      _impressionActivePostId = post.id;
    }
  }

  bool _hasMoreForTab(_FeedTab tab) => tab == _FeedTab.recommendations
      ? _hasMoreRecommendations
      : _hasMoreSubscriptions;

  void _onFeedPageChanged(_FeedTab tab, int index) {
    if (!mounted) return;
    final posts = tab == _FeedTab.recommendations
        ? _postsRecommendations
        : _postsSubscriptions;
    if (posts.isEmpty) return;

    // Хвост со спиннером при подгрузке.
    if (index >= posts.length) {
      if (_feedTab == tab &&
          _hasMoreForTab(tab) &&
          !_isLoadingMore) {
        _loadMore();
      }
      return;
    }

    if (tab == _FeedTab.recommendations) {
      _pageIndexRecommendations = index;
    } else {
      _pageIndexSubscriptions = index;
    }

    if (tab == _FeedTab.recommendations &&
        _feedTab == _FeedTab.recommendations) {
      _impressionActivePostId = posts[index].id;
    }

    if (_feedTab != tab) return;

    final hasMore = _hasMoreForTab(tab);
    if (hasMore && !_isLoadingMore && posts.length >= 2) {
      if (index >= posts.length - 2) {
        _loadMore();
      }
    } else if (hasMore && !_isLoadingMore && posts.length == 1 && index == 0) {
      _loadMore();
    }
    _precacheNeighborsForCurrentFeedPost();
  }

  /// После полного сброса ленты (например первый заход): обе вкладки с начала.
  void _resetAllFeedPagesAfterFullReload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void jump(PageController c) {
        if (c.hasClients) c.jumpToPage(0);
      }
      jump(_pageRecommendationsController);
      jump(_pageSubscriptionsController);
      _pageIndexRecommendations = 0;
      _pageIndexSubscriptions = 0;
      _lastPrecachedFeedIndex = null;
      if (_postsRecommendations.isNotEmpty) {
        _impressionActivePostId = _postsRecommendations.first.id;
      } else {
        _impressionActivePostId = null;
      }
      _precacheFeedHead(_postsRecommendations);
      _precacheFeedHead(_postsSubscriptions);
      _precacheNeighborsForCurrentFeedPost();
    });
  }

  /// Картинки поста + аватар (как в [CachedAvatar] на карточке).
  void _precachePostImages(BuildContext context, PostEntity p) {
    for (final url in p.displayImageUrls) {
      if (url.trim().isEmpty) continue;
      unawaited(
        precacheImage(CachedNetworkImageProvider(url), context),
      );
    }
    final av = p.userAvatarUrl;
    if (av != null && av.isNotEmpty) {
      unawaited(
        precacheImage(
          CachedNetworkImageProvider('$av?uid=${p.userId}'),
          context,
        ),
      );
    }
  }

  /// Первые карточки после загрузки страницы.
  void _precacheFeedHead(List<PostEntity> posts) {
    if (!mounted || posts.isEmpty) return;
    final ctx = context;
    final n = posts.length < 3 ? posts.length : 3;
    for (var i = 0; i < n; i++) {
      _precachePostImages(ctx, posts[i]);
    }
  }

  /// Следующие 1–2 поста относительно текущего скролла (TikTok-лента).
  void _precacheNeighborsForCurrentFeedPost() {
    if (!mounted) return;
    final posts = _posts;
    if (posts.isEmpty) return;
    final h = _feedItemHeight;
    if (h == null || h <= 0) return;
    final idx = _activeFeedPageIndex.clamp(0, posts.length - 1);
    if (_lastPrecachedFeedIndex == idx) return;
    _lastPrecachedFeedIndex = idx;
    final ctx = context;
    for (final off in [1, 2]) {
      final j = idx + off;
      if (j < posts.length) {
        _precachePostImages(ctx, posts[j]);
      }
    }
  }

  void _schedulePrecacheAfterFeedUpdate(_FeedTab loadedTab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_feedTab != loadedTab) return;
      final posts =
          loadedTab == _FeedTab.recommendations
              ? _postsRecommendations
              : _postsSubscriptions;
      _lastPrecachedFeedIndex = null;
      _precacheFeedHead(posts);
      _precacheNeighborsForCurrentFeedPost();
    });
  }

  /// Аватары и превью картинок сторис в полосе над лентой.
  void _precacheStoryStripMedia() {
    if (!mounted || _storyGroups.isEmpty) return;
    final ctx = context;
    // Smaller initial media warmup reduces launch-time pressure.
    for (final g in _storyGroups.take(8)) {
      final av = g.userAvatarUrl;
      if (av != null && av.isNotEmpty) {
        unawaited(
          precacheImage(
            CachedNetworkImageProvider('$av?uid=${g.userId}'),
            ctx,
          ),
        );
      }
      final story = g.firstStory;
      if (story.imageUrl.trim().isNotEmpty) {
        unawaited(
          precacheImage(
            CachedNetworkImageProvider(story.imageUrl),
            ctx,
          ),
        );
      }
    }
  }

  void _applyWarmCache(_MainHomeWarmCache cache) {
    _postsRecommendations
      ..clear()
      ..addAll(cache.postsRecommendations);
    _postsSubscriptions
      ..clear()
      ..addAll(cache.postsSubscriptions);
    _cursorRecommendations = cache.cursorRecommendations;
    _cursorSubscriptions = cache.cursorSubscriptions;
    _hasMoreRecommendations = cache.hasMoreRecommendations;
    _hasMoreSubscriptions = cache.hasMoreSubscriptions;
    _storyGroups = cache.storyGroups;
    _newStoriesByUserId = cache.newStoriesByUserId;
    _storyNotesByUserId = cache.storyNotesByUserId;
    _feedTab = _FeedTab.recommendations;
    _initialLoading = false;
  }

  void _storeWarmCache() {
    final uid = _currentUserId;
    if (uid == null) return;
    _warmCache = _MainHomeWarmCache(
      createdAt: DateTime.now(),
      userId: uid,
      postsRecommendations: List<PostEntity>.from(_postsRecommendations),
      postsSubscriptions: List<PostEntity>.from(_postsSubscriptions),
      cursorRecommendations: _cursorRecommendations,
      cursorSubscriptions: _cursorSubscriptions,
      hasMoreRecommendations: _hasMoreRecommendations,
      hasMoreSubscriptions: _hasMoreSubscriptions,
      storyGroups: List<StoryGroupEntity>.from(_storyGroups),
      newStoriesByUserId: Map<String, bool>.from(_newStoriesByUserId),
      storyNotesByUserId: Map<String, String>.from(_storyNotesByUserId),
    );
  }

  Future<void> _loadInitial({bool showLoading = true}) async {
    final authState = context.read<AuthBloc>().state;
    final activeUserId =
        authState is AuthAuthenticated ? authState.user.id : null;
    _currentUserId = activeUserId;
    _feedTab = _FeedTab.recommendations;
    _invalidateFollowingIdsCache();
    if (showLoading) {
      setState(() => _initialLoading = true);
    }
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
      _resetAllFeedPagesAfterFullReload();
      _storeWarmCache();
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
    if (tab == _FeedTab.recommendations) {
      if (_isFetchingRecommendations) return;
      _isFetchingRecommendations = true;
    } else {
      if (_isFetchingSubscriptions) return;
      _isFetchingSubscriptions = true;
    }
    final repo = context.read<PostRepository>();
    final followingIds = await _getFollowingUserIdsCached();

    try {
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
        _schedulePrecacheAfterFeedUpdate(_FeedTab.recommendations);
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
      _schedulePrecacheAfterFeedUpdate(_FeedTab.subscriptions);
    } finally {
      if (tab == _FeedTab.recommendations) {
        _isFetchingRecommendations = false;
      } else {
        _isFetchingSubscriptions = false;
      }
    }
  }

  void _onFeedTabChanged(_FeedTab tab) {
    if (_feedTab == tab) return;
    if (tab == _FeedTab.subscriptions) {
      _cancelImpressionTimer();
    }
    _lastPrecachedFeedIndex = null;
    setState(() => _feedTab = tab);
    if (tab == _FeedTab.recommendations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncVisiblePostForImpression();
        _ensureImpressionTimer();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_feedTab != tab) return;
      final posts = tab == _FeedTab.recommendations
          ? _postsRecommendations
          : _postsSubscriptions;
      _precacheFeedHead(posts);
      _precacheNeighborsForCurrentFeedPost();
    });
    final tabEmpty = tab == _FeedTab.recommendations
        ? _postsRecommendations.isEmpty
        : _postsSubscriptions.isEmpty;
    if (tabEmpty) {
      unawaited(_fetchPageForTab(tab, reset: true));
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    final now = DateTime.now();
    final last = _lastLoadMoreAt;
    if (last != null && now.difference(last) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastLoadMoreAt = now;
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
      final ids = {...groups.map((e) => e.userId)};
      if (_currentUserId != null) ids.add(_currentUserId!);
      final notesMap = <String, String>{};
      if (ids.isNotEmpty) {
        try {
          final rows = await supa.Supabase.instance.client
              .from(SupabaseConstants.userStorySettingsTable)
              .select('user_id,story_note')
              .inFilter('user_id', ids.toList(growable: false));
          for (final row in (rows as List<dynamic>)) {
            final map = row as Map<String, dynamic>;
            final id = (map['user_id'] ?? '').toString();
            final note = (map['story_note'] ?? '').toString().trim();
            if (id.isNotEmpty && note.isNotEmpty) {
              notesMap[id] = note;
            }
          }
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        // Keep last stories while background refresh is loading if new set is empty.
        if (groups.isNotEmpty || _storyGroups.isEmpty) {
          _storyGroups = groups;
          _newStoriesByUserId = nextMap;
          _storyNotesByUserId = notesMap;
        }
      });
      _storeWarmCache();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _precacheStoryStripMedia();
      });
    } catch (_) {
      // Не очищаем уже загруженные сторис при временной ошибке,
      // чтобы блок сторис в ленте не становился пустым.
    }
  }

  Future<List<StoryGroupEntity>> _filterStoriesByFollowing(
    List<StoryGroupEntity> groups,
  ) async {
    final uid = _currentUserId;
    if (uid == null || groups.isEmpty) return groups;
    try {
      final followingIds = await _getFollowingUserIdsCached();
      final set = followingIds.toSet();
      return groups
          .where((g) => g.userId == uid || set.contains(g.userId))
          .toList(growable: false);
    } catch (_) {
      return groups;
    }
  }

  void _invalidateFollowingIdsCache() {
    _followingIdsCache = null;
    _followingIdsCacheUserId = null;
    _followingIdsLoadFuture = null;
  }

  Future<List<String>> _getFollowingUserIdsCached() async {
    final uid = _currentUserId;
    if (uid == null) return const [];
    if (_followingIdsCache != null && _followingIdsCacheUserId == uid) {
      return _followingIdsCache!;
    }
    _followingIdsLoadFuture ??= _loadFollowingUserIdsForUser(uid);
    return _followingIdsLoadFuture!;
  }

  Future<List<String>> _loadFollowingUserIdsForUser(String uid) async {
    try {
      final profiles =
          await context.read<ProfileRepository>().getFollowingUsers(uid);
      final ids = profiles.map((p) => p.id).toList(growable: false);
      if (mounted && _currentUserId == uid) {
        _followingIdsCache = ids;
        _followingIdsCacheUserId = uid;
      }
      return ids;
    } catch (_) {
      return const [];
    } finally {
      _followingIdsLoadFuture = null;
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
    String enc(String value) => Uri.encodeComponent(value);
    final primaryImage = post.displayImageUrls.isNotEmpty
        ? post.displayImageUrls.first
        : '';
    final shareText =
        '__post__|${enc(post.id)}|${enc(primaryImage)}|${enc(post.caption.trim())}|'
        '${enc(post.userName ?? 'Пользователь')}|${enc(post.videoUrl ?? '')}|'
        '${post.likesCount}|${post.commentsCount}|${post.repostsCount}';
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

  /// Вертикальная лента «как в TikTok»: одна публикация на экран, свайп вверх/вниз.
  Widget _buildVerticalFeed({
    required _FeedTab tab,
    required List<PostEntity> posts,
    required PageController controller,
    required double itemHeight,
  }) {
    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            tab == _FeedTab.subscriptions
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

    final trailingLoader =
        _isLoadingMore && _feedTab == tab && _hasMoreForTab(tab) ? 1 : 0;

    return PageView.builder(
      controller: controller,
      scrollDirection: Axis.vertical,
      onPageChanged: (i) => _onFeedPageChanged(tab, i),
      itemCount: posts.length + trailingLoader,
      itemBuilder: (context, index) {
        if (index >= posts.length) {
          return SizedBox(
            height: itemHeight,
            width: double.infinity,
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(),
              ),
            ),
          );
        }
        final post = posts[index];
        return SizedBox(
          key: ValueKey<String>(post.id),
          height: itemHeight,
          width: double.infinity,
          child: _InstagramPostItem(
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
          ),
        );
      },
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
    final sessionUid = context.select<AuthBloc, String?>((b) {
      final s = b.state;
      return s is AuthAuthenticated ? s.user.id : null;
    });
    final currentUserAvatarUrl = context.select<AuthBloc, String?>((b) {
      final s = b.state;
      return s is AuthAuthenticated ? s.user.avatarUrl : null;
    });
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
          const NotificationActivityPeekBar(),
          const _FeedNotificationsButton(),
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
            unawaited(_reloadHomeAfterAuthUserChange());
          }
        },
        child: _initialLoading
            ? const Center(child: AppLoading())
            : Column(
                children: [
                  ChatStoriesFriendsStrip(
                    groups: _storyGroups,
                    newStoriesByUserId: _newStoriesByUserId,
                    storyNotesByUserId: const <String, String>{},
                    enableNotes: false,
                    currentUserId: sessionUid,
                    currentUserAvatarUrl: currentUserAvatarUrl,
                    onOwnNoteTap: (_) {},
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

                        return IndexedStack(
                          index: _feedTab == _FeedTab.recommendations ? 0 : 1,
                          sizing: StackFit.expand,
                          children: [
                            _buildVerticalFeed(
                              tab: _FeedTab.recommendations,
                              posts: _postsRecommendations,
                              controller: _pageRecommendationsController,
                              itemHeight: itemHeight,
                            ),
                            _buildVerticalFeed(
                              tab: _FeedTab.subscriptions,
                              posts: _postsSubscriptions,
                              controller: _pageSubscriptionsController,
                              itemHeight: itemHeight,
                            ),
                          ],
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

class _MainHomeWarmCache {
  const _MainHomeWarmCache({
    required this.createdAt,
    required this.userId,
    required this.postsRecommendations,
    required this.postsSubscriptions,
    required this.cursorRecommendations,
    required this.cursorSubscriptions,
    required this.hasMoreRecommendations,
    required this.hasMoreSubscriptions,
    required this.storyGroups,
    required this.newStoriesByUserId,
    required this.storyNotesByUserId,
  });

  final DateTime createdAt;
  final String userId;
  final List<PostEntity> postsRecommendations;
  final List<PostEntity> postsSubscriptions;
  final int cursorRecommendations;
  final int cursorSubscriptions;
  final bool hasMoreRecommendations;
  final bool hasMoreSubscriptions;
  final List<StoryGroupEntity> storyGroups;
  final Map<String, bool> newStoriesByUserId;
  final Map<String, String> storyNotesByUserId;
}

class _FeedNotificationsButton extends StatefulWidget {
  const _FeedNotificationsButton();

  @override
  State<_FeedNotificationsButton> createState() =>
      _FeedNotificationsButtonState();
}

class _FeedNotificationsButtonState extends State<_FeedNotificationsButton> {
  int _unread = 0;
  NotificationActivityPeekBus? _peekBus;

  @override
  void initState() {
    super.initState();
    _peekBus = context.read<NotificationActivityPeekBus>();
    _peekBus!.unreadInvalidateTick.addListener(_onUnreadInvalidateTick);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUnread());
  }

  @override
  void dispose() {
    _peekBus?.unreadInvalidateTick.removeListener(_onUnreadInvalidateTick);
    super.dispose();
  }

  void _onUnreadInvalidateTick() {
    _loadUnread();
  }

  Future<void> _loadUnread() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null || !mounted) return;
    try {
      final n = await context
          .read<NotificationsRepository>()
          .getUnreadCount(userId);
      if (mounted) setState(() => _unread = n);
    } catch (_) {
      if (mounted) setState(() => _unread = 0);
    }
  }

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

    return IconButton(
      onPressed: () async {
        await context.push('/notifications');
        if (mounted) await _loadUnread();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.favorite_border_rounded),
          if (_unread > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 16),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade600,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  formatNotificationBadgeCount(_unread),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InstagramPostItem extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final p = post;
    final mediaHeight = height;

    return RepaintBoundary(
      child: SizedBox(
        height: mediaHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: DoubleTapLikeBurst(
                onDoubleTapLike: onLike,
                shouldTriggerLike: () => !p.isLikedByMe,
                showPersistentLikeIndicator: true,
                isLiked: p.isLikedByMe,
                child: _PostMedia(
                  imageUrls: p.displayImageUrls,
                  videoUrl: p.videoUrl,
                  fillHeight: mediaHeight,
                ),
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
                    UserAvatarTap(
                      userId: p.userId,
                      avatarUrl: p.userAvatarUrl,
                      radius: 18,
                      currentUserId: currentUserId,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: UsernameTap(
                        userId: p.userId,
                        username: p.userName ?? 'Пользователь',
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
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).padding.bottom,
                ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      border: Border(
                        top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                    ),
                    child: _PostActionsBar(
                      isLikedByMe: p.isLikedByMe,
                      likesCount: p.likesCount,
                      commentsCount: p.commentsCount,
                      repostsCount: p.repostsCount,
                      viewsCount: p.viewsCount,
                      showViews: (p.videoUrl ?? '').trim().isNotEmpty,
                      isRepostedByMe: p.isRepostedByMe,
                      isSavedByMe: p.isSavedByMe,
                      onLike: onLike,
                      onComment: onComment,
                      onRepost: onRepost,
                      onShare: onShare,
                      onSave: onSave,
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PostActionsBar extends StatelessWidget {
  const _PostActionsBar({
    required this.isLikedByMe,
    required this.likesCount,
    required this.commentsCount,
    required this.repostsCount,
    required this.viewsCount,
    required this.showViews,
    required this.isRepostedByMe,
    required this.isSavedByMe,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onShare,
    required this.onSave,
  });

  final bool isLikedByMe;
  final int likesCount;
  final int commentsCount;
  final int repostsCount;
  final int viewsCount;
  final bool showViews;
  final bool isRepostedByMe;
  final bool isSavedByMe;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onShare;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionButton(
          icon: isLikedByMe ? Icons.favorite : Icons.favorite_border,
          iconColor: isLikedByMe ? Colors.redAccent : Colors.white,
          label: 'Лайк',
          count: likesCount,
          onTap: onLike,
        ),
        _ActionButton(
          icon: Icons.chat_bubble_outline_rounded,
          iconColor: Colors.white,
          label: 'Коммент',
          count: commentsCount,
          onTap: onComment,
        ),
        if (showViews)
          _ActionButton(
            icon: Icons.play_arrow_rounded,
            iconColor: Colors.white,
            label: 'Просмотр',
            count: viewsCount,
            onTap: () {},
          ),
        _ActionButton(
          icon: isRepostedByMe ? Icons.repeat : Icons.repeat_outlined,
          iconColor: isRepostedByMe ? Colors.cyanAccent : Colors.white,
          label: 'Репост',
          count: repostsCount,
          onTap: onRepost,
        ),
        _ShareButton(
          onTap: onShare,
          label: 'Поделиться',
        ),
        const Spacer(),
        _SaveButton(
          onTap: onSave,
          isSaved: isSavedByMe,
        ),
      ],
    );
  }
}

class _PostMedia extends StatelessWidget {
  const _PostMedia({
    required this.imageUrls,
    required this.videoUrl,
    required this.fillHeight,
  });

  final List<String> imageUrls;
  final String? videoUrl;
  final double fillHeight;

  @override
  Widget build(BuildContext context) {
    if (videoUrl != null && videoUrl!.isNotEmpty) {
      return _VideoMedia(videoUrl: videoUrl!);
    }

    if (imageUrls.isNotEmpty) {
      return PostNetworkPhotoGallery(
        urls: imageUrls,
        height: fillHeight,
        borderRadius: 0,
        viewportFraction: imageUrls.length > 1 ? 0.9 : 1,
      );
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
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final c = await createCachedVideoController(widget.videoUrl);
      await c.initialize();
      c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _controller = c;
      setState(() => _ready = true);
      c.play();
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const Center(child: CircularProgressIndicator());
    }
    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                });
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(controller),
                  if (!controller.value.isPlaying)
                    const Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(14),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
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
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(
          width: 44,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: Colors.white,
                size: 21,
              ),
              const SizedBox(height: 2),
              const Text(
                'Сохран.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
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
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: SizedBox(
          width: 52,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.send_outlined, color: Colors.white, size: 21),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
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

