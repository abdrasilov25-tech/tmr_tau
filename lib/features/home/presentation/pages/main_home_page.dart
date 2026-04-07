import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/following/following_change_bus.dart';
import '../../../live_streaming/domain/entities/live_room_entity.dart';
import '../../../live_streaming/domain/repositories/live_streaming_repository.dart';
import '../../../../core/media/cached_video_controller.dart';
import '../../../../core/utils/notification_badge_format.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/double_tap_like_burst.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/storage/live_ended_dismiss_storage.dart';
import '../../../live_battle/domain/entities/battle_history_entry.dart';
import '../../../live_battle/domain/repositories/live_battle_repository.dart';
import '../../../chat/presentation/widgets/chat_stories_friends_strip.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../../../notifications/domain/repositories/notifications_repository.dart';
import '../../../notifications/presentation/notification_activity_peek_bus.dart';
import '../../../notifications/presentation/notification_tab_badge_controller.dart';
import '../../../notifications/presentation/widgets/notification_activity_peek_bar.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/entities/publication_feed_page_result.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../post/presentation/widgets/post_author_follow_pill.dart';
import 'reels_feed_page.dart';
import '../../../post/presentation/widgets/post_feed_overflow_menu.dart';
import '../../../post/presentation/widgets/post_photo_gallery.dart';
import '../../../post/presentation/widgets/post_share_sheet.dart';
import '../widgets/user_avatar_tap.dart';

/// Безопасно для виджет-тестов и до [Supabase.initialize]: иначе `Supabase.instance` бросает.
String? _supabaseAuthUserIdOrNull() {
  try {
    return supa.Supabase.instance.client.auth.currentUser?.id;
  } catch (e) {
    return null;
  }
}

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
  /// Только видео — вертикальный бесконечный Reels-фид (Instagram-style).
  reels,
  /// «Для вас» — не от себя и не от подписок; персональный скор (лайки/сохранения/просмотры/хэштеги).
  recommendations,
  /// Только авторы из подписок.
  subscriptions,
  /// Активные прямые эфиры и батлы.
  live,
}

extension _FeedTabIndex on _FeedTab {
  int get pageIndex {
    switch (this) {
      case _FeedTab.reels:           return 0;
      case _FeedTab.recommendations: return 1;
      case _FeedTab.subscriptions:   return 2;
      case _FeedTab.live:            return 3;
    }
  }

  static _FeedTab fromIndex(int i) {
    switch (i) {
      case 0: return _FeedTab.reels;
      case 1: return _FeedTab.recommendations;
      case 2: return _FeedTab.subscriptions;
      default: return _FeedTab.live;
    }
  }
}

class _MainHomePageState extends State<MainHomePage> {
  static const int _pageSize = 10;
  /// Дольше, чем раньше: при возврате на вкладку «Публикации» не сбрасываем ленту.
  static const Duration _warmCacheTtl = Duration(minutes: 45);
  static _MainHomeWarmCache? _warmCache;

  /// Отдельный вертикальный «экран» на вкладку — свайп как в TikTok.
  late final PageController _pageRecommendationsController;
  late final PageController _pageSubscriptionsController;
  /// Горизонтальный PageController для переключения вкладок свайпом (как TikTok).
  late final PageController _tabPageController;

  /// Индекс текущей «карточки» в вертикальной ленте (отдельно для каждой вкладки).
  int _pageIndexRecommendations = 0;
  int _pageIndexSubscriptions = 0;

  int get _activeFeedPageIndex {
    switch (_feedTab) {
      case _FeedTab.reels: return 0;
      case _FeedTab.recommendations: return _pageIndexRecommendations;
      case _FeedTab.subscriptions: return _pageIndexSubscriptions;
      case _FeedTab.live: return 0;
    }
  }

  /// Высота одной карточки ленты (viewport [PageView]).
  double? _feedItemHeight;
  String? _impressionActivePostId;
  Timer? _impressionTimer;

  bool _initialLoading = true;
  bool _isLoadingMore = false;
  bool _isFetchingRecommendations = false;
  bool _isFetchingSubscriptions = false;
  DateTime? _lastLoadMoreAt;

  _FeedTab _feedTab = _FeedTab.reels;

  final List<PostEntity> _postsRecommendations = [];
  final List<PostEntity> _postsSubscriptions = [];

  int _cursorRecommendations = 0;
  int _cursorSubscriptions = 0;

  bool _hasMoreRecommendations = true;
  bool _hasMoreSubscriptions = true;

  /// Текущая видимая лента (по выбранной вкладке).
  List<PostEntity> get _posts {
    switch (_feedTab) {
      case _FeedTab.reels: return _postsRecommendations;
      case _FeedTab.recommendations: return _postsRecommendations;
      case _FeedTab.subscriptions: return _postsSubscriptions;
      case _FeedTab.live: return const [];
    }
  }

  bool get _hasMore {
    switch (_feedTab) {
      case _FeedTab.reels: return _hasMoreRecommendations;
      case _FeedTab.recommendations: return _hasMoreRecommendations;
      case _FeedTab.subscriptions: return _hasMoreSubscriptions;
      case _FeedTab.live: return false;
    }
  }
  List<StoryGroupEntity> _storyGroups = const [];
  Map<String, bool> _newStoriesByUserId = const {};
  Map<String, String> _storyNotesByUserId = const {};

  String? _currentUserId;

  /// Подписок больше не запрашиваем на каждый chunk ленты и второй раз для сторис — один запрос на сессию / после сброса.
  List<String>? _followingIdsCache;
  String? _followingIdsCacheUserId;
  Future<List<String>>? _followingIdsLoadFuture;

  StreamSubscription<void>? _followingChangeSub;

  /// Последний индекс, для которого уже вызывали precache соседей (избегаем лишней работы при скролле).
  int? _lastPrecachedFeedIndex;

  @override
  void initState() {
    super.initState();
    _pageRecommendationsController = PageController();
    _pageSubscriptionsController = PageController();
    _tabPageController = PageController();

    // Текущий userId: AuthBloc; если ещё не успел эмитнуть — fallback на сессию Supabase.
    final authState = context.read<AuthBloc>().state;
    _currentUserId = authState is AuthAuthenticated
        ? authState.user.id
        : null;
    _currentUserId ??= _supabaseAuthUserIdOrNull();

    _followingChangeSub =
        FollowingChangeBus.instance.stream.listen((_) {
      if (!mounted) return;
      _invalidateFollowingIdsCache();
      unawaited(_syncFollowFlagsAfterFollowingChange());
    });

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
    // При первом экране Reels не блокируем UI тяжёлой загрузкой других лент.
    if (_feedTab == _FeedTab.reels) {
      await _loadStories();
      if (!mounted) return;
      if (_initialLoading) {
        setState(() => _initialLoading = false);
      }
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (_postsRecommendations.isNotEmpty || _postsSubscriptions.isNotEmpty) {
          return;
        }
        unawaited(_silentRefreshFeeds());
      });
      return;
    }

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
      final recSub = await Future.wait([
        repo.getPublicationsFeedRecommendations(
          currentUserId: _currentUserId,
          followingUserIds: followingIds,
          limit: _pageSize,
          discoveryDbOffset: 0,
        ),
        repo.getPublicationsFeedSubscriptions(
          currentUserId: _currentUserId,
          followingUserIds: followingIds,
          limit: _pageSize,
          offset: 0,
        ),
      ]);
      final rec = recSub[0];
      final sub = recSub[1];
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
    } catch (e) {
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
    _followingChangeSub?.cancel();
    _cancelImpressionTimer();
    _pageRecommendationsController.dispose();
    _pageSubscriptionsController.dispose();
    _tabPageController.dispose();
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
    _currentUserId = activeUserId ?? _supabaseAuthUserIdOrNull();
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
      final repo = context.read<PostRepository>();
      final followingIds = await _getFollowingUserIdsCached();
      final recSub = await Future.wait<PublicationFeedPageResult>([
        repo.getPublicationsFeedRecommendations(
          currentUserId: _currentUserId,
          followingUserIds: followingIds,
          limit: _pageSize,
          discoveryDbOffset: 0,
        ),
        repo.getPublicationsFeedSubscriptions(
          currentUserId: _currentUserId,
          followingUserIds: followingIds,
          limit: _pageSize,
          offset: 0,
        ),
      ]);
      final rec = recSub[0];
      final sub = recSub[1];
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
        _initialLoading = false;
      });
      _resetAllFeedPagesAfterFullReload();
      _storeWarmCache();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_tabPageController.hasClients) {
          _tabPageController.jumpToPage(_feedTab.pageIndex);
        }
        if (_feedTab == _FeedTab.recommendations) {
          _syncVisiblePostForImpression();
          _ensureImpressionTimer();
        }
        _precacheFeedHead(_postsRecommendations);
        _precacheFeedHead(_postsSubscriptions);
        _lastPrecachedFeedIndex = null;
        _precacheNeighborsForCurrentFeedPost();
      });
      debugPrint(
        '[MainHomePage] loaded feeds rec=${rec.posts.length} sub=${sub.posts.length} tab=$_feedTab',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialLoading = false;
        _hasMoreRecommendations = false;
        _hasMoreSubscriptions = false;
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
    if (tab != _FeedTab.recommendations) {
      _cancelImpressionTimer();
    }
    _lastPrecachedFeedIndex = null;
    setState(() => _feedTab = tab);

    // Пока скелетон вместо PageView — только обновляем выбранную вкладку на макете.
    if (!_initialLoading && _tabPageController.hasClients) {
      _tabPageController.animateToPage(
        tab.pageIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeInOut,
      );
    }

    if (_initialLoading) return;

    if (tab == _FeedTab.recommendations) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncVisiblePostForImpression();
        _ensureImpressionTimer();
      });
    }
    // Reels и Live управляют своим контентом сами — не трогаем вертикальные ленты.
    if (tab == _FeedTab.live || tab == _FeedTab.reels) return;
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
    // Синхронно блокируем повторный вызов до завершения запроса.
    _isLoadingMore = true;
    _lastLoadMoreAt = now;
    setState(() {});
    try {
      await _fetchPageForTab(_feedTab, reset: false);
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    } catch (e) {
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
        } catch (e) { debugPrint('$e'); }
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
    } catch (e) {
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
    } catch (e) {
      return groups;
    }
  }

  void _invalidateFollowingIdsCache() {
    _followingIdsCache = null;
    _followingIdsCacheUserId = null;
    _followingIdsLoadFuture = null;
  }

  void _reconcileFollowFlagsInLists(Set<String> followingIds) {
    final uid = _currentUserId;
    void reconcile(List<PostEntity> list) {
      for (var i = 0; i < list.length; i++) {
        final p = list[i];
        if (uid != null && p.userId == uid) continue;
        final should = followingIds.contains(p.userId);
        if (p.isFollowingAuthor != should) {
          list[i] = p.copyWith(isFollowingAuthor: should);
        }
      }
    }

    reconcile(_postsRecommendations);
    reconcile(_postsSubscriptions);
  }

  Future<void> _syncFollowFlagsAfterFollowingChange() async {
    final uid = _currentUserId;
    if (uid == null || !mounted) return;
    try {
      final ids = await _getFollowingUserIdsCached();
      if (!mounted) return;
      setState(() => _reconcileFollowFlagsInLists(ids.toSet()));
    } catch (e) { debugPrint('$e'); }
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
    } catch (e) {
      return const [];
    } finally {
      _followingIdsLoadFuture = null;
    }
  }

  Future<void> _openAddStoryAndRefresh() async {
    final uid = _currentUserId ?? _supabaseAuthUserIdOrNull();
    if (uid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы снять сторис')),
      );
      return;
    }
    await context.push('/story-camera');
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

    try {
      await context.read<PostRepository>().toggleLike(post.id, userId);
      if (!mounted) return;
      await _refreshPost(post.id);
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      await _refreshPost(post.id);
    } catch (e) {
      if (!mounted) return;
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
      if (!mounted) return;
      await _refreshPost(post.id);
    } catch (e) {
      if (!mounted) return;
      await _refreshPost(post.id);
    }
  }

  Future<void> _toggleFollow(PostEntity post) async {
    final userId = _currentUserId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы подписаться')),
      );
      return;
    }
    if (userId == post.userId) return;

    final authorId = post.userId;
    final was = post.isFollowingAuthor;

    void applyFollow(bool following) {
      for (var i = 0; i < _postsRecommendations.length; i++) {
        if (_postsRecommendations[i].userId == authorId) {
          _postsRecommendations[i] =
              _postsRecommendations[i].copyWith(isFollowingAuthor: following);
        }
      }
      for (var i = 0; i < _postsSubscriptions.length; i++) {
        if (_postsSubscriptions[i].userId == authorId) {
          _postsSubscriptions[i] =
              _postsSubscriptions[i].copyWith(isFollowingAuthor: following);
        }
      }
    }

    setState(() => applyFollow(!was));
    _invalidateFollowingIdsCache();

    try {
      await context.read<ProfileRepository>().toggleFollow(userId, authorId);
    } catch (e) {
      if (mounted) setState(() => applyFollow(was));
    }
  }

  void _removePostFromFeeds(String postId) {
    if (!mounted) return;
    setState(() {
      _postsRecommendations.removeWhere((p) => p.id == postId);
      _postsSubscriptions.removeWhere((p) => p.id == postId);
    });
  }

  Future<void> _shareToUser(PostEntity post) async {
    if (_currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы поделиться')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PostShareSheet(
        currentUserId: _currentUserId!,
        post: post,
        onAddToStory: () => context.push('/add-story'),
      ),
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
            postRepository: context.read<PostRepository>(),
            currentUserId: _currentUserId,
            onFollow: _currentUserId != null && _currentUserId != post.userId
                ? () => unawaited(_toggleFollow(post))
                : null,
            onLike: () => _toggleLike(post),
            onRepost: () => _toggleRepost(post),
            onSave: () => _toggleSave(post),
            onHidePost: () => _removePostFromFeeds(post.id),
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

  /// Вкладка «Live» — активные эфиры, архив баттлов и завершённые эфиры ведущего.
  Widget _buildLiveTab() => const _MainHomeLiveTab();

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
          onPressed: _openAddStoryAndRefresh,
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
        child: Column(
          children: [
            if (_initialLoading)
              const _StoriesStripSkeleton()
            else
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
              padding: const EdgeInsets.fromLTRB(6, 2, 4, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _PublicationFeedTabStrip(
                        selected: _feedTab,
                        onChanged: _onFeedTabChanged,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Поиск людей и видео',
                    icon: Icon(
                      Icons.search_rounded,
                      size: 26,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.72),
                    ),
                    onPressed: () => context.push('/discover-publications'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final itemHeight =
                          constraints.maxHeight.isFinite &&
                                  constraints.maxHeight > 0
                              ? constraints.maxHeight
                              : h;
                      _feedItemHeight = itemHeight;
                      return PageView(
                        controller: _tabPageController,
                        scrollDirection: Axis.horizontal,
                        physics: const ClampingScrollPhysics(),
                        onPageChanged: (i) {
                          final tab = _FeedTabIndex.fromIndex(i);
                          if (_feedTab != tab) {
                            _onFeedTabChanged(tab);
                          }
                        },
                        children: [
                          const ReelsFeedPage(),
                          _initialLoading
                              ? _VerticalFeedTabSkeleton(height: itemHeight)
                              : _buildVerticalFeed(
                                  tab: _FeedTab.recommendations,
                                  posts: _postsRecommendations,
                                  controller: _pageRecommendationsController,
                                  itemHeight: itemHeight,
                                ),
                          _initialLoading
                              ? _VerticalFeedTabSkeleton(height: itemHeight)
                              : _buildVerticalFeed(
                                  tab: _FeedTab.subscriptions,
                                  posts: _postsSubscriptions,
                                  controller: _pageSubscriptionsController,
                                  itemHeight: itemHeight,
                                ),
                          _initialLoading
                              ? const _LiveTabLoadingShell()
                              : _buildLiveTab(),
                        ],
                      );
                    },
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _StoryCameraEdgeSwipeDetector.edgeWidthLogical,
                    child: _StoryCameraEdgeSwipeDetector(
                      onOpenStoryCamera: () =>
                          unawaited(_openAddStoryAndRefresh()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Левый край ленты: свайп **вправо** открывает камеру сторис (как в Instagram),
/// без перехвата вертикального скролла — зона узкая, поверх ленты.
class _StoryCameraEdgeSwipeDetector extends StatefulWidget {
  const _StoryCameraEdgeSwipeDetector({
    required this.onOpenStoryCamera,
  });

  final VoidCallback onOpenStoryCamera;

  /// Логические пиксели ширины чувствительной полосы (совпадает с Positioned).
  static const double edgeWidthLogical = 28;

  static const double _minFlingVelocity = 380;
  static const double _minDragDx = 56;

  @override
  State<_StoryCameraEdgeSwipeDetector> createState() =>
      _StoryCameraEdgeSwipeDetectorState();
}

class _StoryCameraEdgeSwipeDetectorState
    extends State<_StoryCameraEdgeSwipeDetector> {
  double _accumDx = 0;

  void _maybeOpen(double velocity) {
    if (velocity > _StoryCameraEdgeSwipeDetector._minFlingVelocity ||
        _accumDx >= _StoryCameraEdgeSwipeDetector._minDragDx) {
      widget.onOpenStoryCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => _accumDx = 0,
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx > 0) {
          _accumDx += details.delta.dx;
        }
      },
      onHorizontalDragEnd: (details) {
        _maybeOpen(details.primaryVelocity ?? 0);
        _accumDx = 0;
      },
      onHorizontalDragCancel: () => _accumDx = 0,
    );
  }
}

/// Компактные подписи вкладок ленты — слева, без крупного SegmentedButton.
class _PublicationFeedTabStrip extends StatelessWidget {
  const _PublicationFeedTabStrip({
    required this.selected,
    required this.onChanged,
  });

  final _FeedTab selected;
  final ValueChanged<_FeedTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.55);
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _PublicationFeedTabLabel(
          label: 'Reels',
          selected: selected == _FeedTab.reels,
          subtleColor: subtle,
          scheme: scheme,
          isReels: true,
          onTap: () => onChanged(_FeedTab.reels),
        ),
        Text('·', style: TextStyle(color: subtle, fontSize: 12)),
        _PublicationFeedTabLabel(
          label: 'Рекомендации',
          selected: selected == _FeedTab.recommendations,
          subtleColor: subtle,
          scheme: scheme,
          onTap: () => onChanged(_FeedTab.recommendations),
        ),
        Text('·', style: TextStyle(color: subtle, fontSize: 12)),
        _PublicationFeedTabLabel(
          label: 'Подписки',
          selected: selected == _FeedTab.subscriptions,
          subtleColor: subtle,
          scheme: scheme,
          onTap: () => onChanged(_FeedTab.subscriptions),
        ),
        Text('·', style: TextStyle(color: subtle, fontSize: 12)),
        _PublicationFeedTabLabel(
          label: 'Live',
          selected: selected == _FeedTab.live,
          subtleColor: subtle,
          scheme: scheme,
          isLive: true,
          onTap: () => onChanged(_FeedTab.live),
        ),
      ],
    );
  }
}

class _PublicationFeedTabLabel extends StatelessWidget {
  const _PublicationFeedTabLabel({
    required this.label,
    required this.selected,
    required this.subtleColor,
    required this.scheme,
    required this.onTap,
    this.isLive = false,
    this.isReels = false,
  });

  final String label;
  final bool selected;
  final Color subtleColor;
  final ColorScheme scheme;
  final VoidCallback onTap;
  final bool isLive;
  final bool isReels;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLive) ...[
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEF4444),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                if (isReels) ...[
                  Icon(
                    Icons.play_circle_outline_rounded,
                    size: 13,
                    color: selected
                        ? const Color(0xFF7C3AED)
                        : subtleColor,
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? (isLive
                            ? const Color(0xFFEF4444)
                            : isReels
                                ? const Color(0xFF7C3AED)
                                : scheme.onSurface)
                        : subtleColor,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: selected ? 22 : 0,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: selected
                    ? (isLive
                        ? const Color(0xFFEF4444)
                        : isReels
                            ? const Color(0xFF7C3AED)
                            : scheme.primary.withValues(alpha: 0.85))
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Live tab (active + archives) ───────────────────────────────────────────────

class _MainHomeLiveTab extends StatefulWidget {
  const _MainHomeLiveTab();

  @override
  State<_MainHomeLiveTab> createState() => _MainHomeLiveTabState();
}

class _MainHomeLiveTabState extends State<_MainHomeLiveTab> {
  LiveEndedDismissStorage? _dismissStorage;
  List<LiveRoomEntity> _endedMine = const [];
  List<BattleHistoryEntry> _battleArchive = const [];
  bool _archiveLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initStorageAndArchive());
  }

  Future<void> _initStorageAndArchive() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _dismissStorage = LiveEndedDismissStorage(prefs));
    await _loadArchive();
  }

  Future<void> _loadArchive() async {
    final auth = context.read<AuthBloc>().state;
    final uid = auth is AuthAuthenticated ? auth.user.id : null;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _endedMine = const [];
          _battleArchive = const [];
          _archiveLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _archiveLoading = true);
    try {
      final live = context.read<LiveStreamingRepository>();
      final battle = context.read<LiveBattleRepository>();
      final ended = await live.getMyEndedLiveRooms(limit: 25);
      final hist = await battle.getBattleHistory(uid);
      if (!mounted) return;
      setState(() {
        _endedMine = ended;
        _battleArchive = hist;
        _archiveLoading = false;
      });
    } catch (e) {
      debugPrint('[LiveTab] archive: $e');
      if (mounted) setState(() => _archiveLoading = false);
    }
  }

  Set<String> get _dismissed {
    final auth = context.read<AuthBloc>().state;
    final uid = auth is AuthAuthenticated ? auth.user.id : null;
    final st = _dismissStorage;
    if (uid == null || st == null) return const {};
    return st.dismissedRoomIds(uid);
  }

  Future<void> _dismissEndedRoom(LiveRoomEntity room) async {
    final auth = context.read<AuthBloc>().state;
    final uid = auth is AuthAuthenticated ? auth.user.id : null;
    final st = _dismissStorage;
    if (uid == null || st == null) return;
    await st.dismissRoom(uid, room.id);
    if (mounted) setState(() {});
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '«${room.title.isEmpty ? 'Эфир' : room.title}» убран из списка',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (prev, curr) {
        String? id(AuthState s) =>
            s is AuthAuthenticated ? s.user.id : null;
        return id(prev) != id(curr);
      },
      listener: (context, state) {
        unawaited(_initStorageAndArchive());
      },
      child: StreamBuilder<List<LiveRoomEntity>>(
        stream: context.read<LiveStreamingRepository>().watchActiveLiveRooms(),
        builder: (context, snapshot) {
          final rooms = snapshot.data ?? const [];
          return RefreshIndicator(
            onRefresh: _loadArchive,
            child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => context.push('/live/host'),
                          icon: const Icon(Icons.videocam_rounded),
                          label: const Text('Начать эфир'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/live-battle-lobby'),
                          icon: const Icon(Icons.sports_kabaddi_rounded),
                          label: const Text('Баттл'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_archiveLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                ),
              SliverToBoxAdapter(child: _buildPastLivesSection(context)),
              SliverToBoxAdapter(child: _buildBattlesSection(context)),
              if (snapshot.connectionState == ConnectionState.waiting &&
                  rooms.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LiveRoomsLoadingSkeleton(),
                )
              else if (rooms.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.live_tv_outlined,
                          size: 64,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Нет активных эфиров',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.45),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Начните первый или ждите других',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.3),
                              ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Text(
                      'Сейчас в эфире',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: rooms.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final room = rooms[i];
                      return _LiveRoomCard(
                        room: room,
                        onTap: () => context.push('/live/watch/${room.id}'),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
        },
      ),
    );
  }

  Widget _buildPastLivesSection(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) return const SizedBox.shrink();
    if (_archiveLoading) return const SizedBox.shrink();

    final hidden = _dismissed;
    final visible = _endedMine.where((r) => !hidden.contains(r.id)).toList();
    if (visible.isEmpty && _endedMine.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Text(
          'Завершённые эфиры появятся здесь после выхода из прямого эфира.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.45),
              ),
        ),
      );
    }
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Мои эфиры',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Нажмите на строку, чтобы убрать её из списка (эфир в базе сохраняется).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
                ),
          ),
          const SizedBox(height: 10),
          ...visible.map((room) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => unawaited(_dismissEndedRoom(room)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.history_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                room.title.isEmpty ? 'Эфир' : room.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (room.endedAt != null)
                                Text(
                                  _formatEnded(room.endedAt!),
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBattlesSection(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated ||
        _battleArchive.isEmpty ||
        _archiveLoading) {
      return const SizedBox.shrink();
    }
    final preview = _battleArchive.take(5).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.sports_kabaddi_rounded,
                size: 20,
                color: Theme.of(context).colorScheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text(
                'Баттлы',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => context.push('/live-battle-history'),
                child: const Text('Все'),
              ),
            ],
          ),
          Text(
            'Завершённые баттлы хранятся здесь и в полной истории.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.45),
                ),
          ),
          const SizedBox(height: 10),
          ...preview.map((e) {
            final me = auth.user.id;
            final won = e.winnerId == me;
            final draw = e.winnerId == null;
            final label = won ? 'Победа' : (draw ? 'Ничья' : 'Поражение');
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                tileColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.35),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(
                  won
                      ? Icons.emoji_events_outlined
                      : draw
                          ? Icons.handshake_outlined
                          : Icons.sports_kabaddi_rounded,
                  color: won
                      ? const Color(0xFF22C55E)
                      : draw
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFFEF4444),
                ),
                title: Text(
                  '${e.scoreA} : ${e.scoreB}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text('$label · ${_formatEnded(e.createdAt)}'),
                onTap: () => context.push('/live-battle-history'),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatEnded(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$d.$mo $h:$mi';
  }
}

// ─── Live room card ───────────────────────────────────────────────────────────

class _LiveRoomCard extends StatelessWidget {
  const _LiveRoomCard({required this.room, required this.onTap});

  final LiveRoomEntity room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.live_tv_rounded,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    room.title.isNotEmpty ? room.title : 'Прямой эфир',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'LIVE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: const Color(0xFFEF4444),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 22),
          ],
        ),
      ),
    );
  }
}

class _StoriesStripSkeleton extends StatelessWidget {
  const _StoriesStripSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final hi = Theme.of(context).colorScheme.surfaceContainerHigh;
    return SizedBox(
      height: 96,
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: hi,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          itemCount: 8,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) => Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _VerticalFeedTabSkeleton extends StatelessWidget {
  const _VerticalFeedTabSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final hi = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: hi,
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveTabLoadingShell extends StatelessWidget {
  const _LiveTabLoadingShell();

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/live/host'),
                    icon: const Icon(Icons.videocam_rounded),
                    label: const Text('Начать эфир'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/live-battle-lobby'),
                    icon: const Icon(Icons.sports_kabaddi_rounded),
                    label: const Text('Баттл'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverFillRemaining(
          hasScrollBody: false,
          child: _LiveRoomsLoadingSkeleton(),
        ),
      ],
    );
  }
}

class _LiveRoomsLoadingSkeleton extends StatelessWidget {
  const _LiveRoomsLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final hi = Theme.of(context).colorScheme.surfaceContainerHigh;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Shimmer.fromColors(
        baseColor: base,
        highlightColor: hi,
        child: Column(
          children: List.generate(
            5,
            (_) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
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
    unawaited(context.read<NotificationTabBadgeController>().refresh());
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
    } catch (e) {
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
    required this.postRepository,
    required this.currentUserId,
    this.onFollow,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onSave,
    required this.onShare,
    required this.onHidePost,
  });

  final double height;
  final PostEntity post;
  final PostRepository postRepository;
  final String? currentUserId;
  final VoidCallback? onFollow;

  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onSave;
  final VoidCallback onShare;
  final VoidCallback onHidePost;

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
                    if (onFollow != null) ...[
                      const SizedBox(width: 8),
                      PostAuthorFollowPill(
                        isFollowing: p.isFollowingAuthor,
                        onTap: onFollow!,
                        compact: true,
                      ),
                    ],
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      icon: const Icon(Icons.more_vert_rounded,
                          color: Colors.white, size: 24),
                      onPressed: () => showPostFeedOverflowMenu(
                        context,
                        post: p,
                        postRepository: postRepository,
                        goRouter: GoRouter.of(context),
                        currentUserId: currentUserId,
                        onSave: onSave,
                        onHide: onHidePost,
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
        enableTapToOpenFullscreen: false,
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready || _controller == null) return;
    // Приостанавливаем видео когда вкладка скрыта (IndexedStack, Navigator).
    if (TickerMode.of(context)) {
      _controller!.play();
    } else {
      _controller!.pause();
    }
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
      // Играем только если вкладка активна.
      if (TickerMode.of(context)) c.play();
    } catch (e) {
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


