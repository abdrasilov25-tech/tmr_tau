import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../profile/domain/entities/seller_profile_entity.dart';
import '../../../profile/domain/repositories/profile_repository.dart';
import '../../../../core/widgets/cached_avatar.dart';

/// Кэш результатов поиска в памяти (одна сессия приложения), без «вечной» подгрузки.
class _PublicationDiscoverSearchCache {
  _PublicationDiscoverSearchCache._();

  static const ttl = Duration(minutes: 5);
  static final Map<String, List<SellerProfileEntity>> _users = {};
  static final Map<String, DateTime> _usersAt = {};
  static final Map<String, List<PostEntity>> _videosFirstPage = {};
  static final Map<String, DateTime> _videosAt = {};
  static final List<String> _recentQueries = <String>[];
  static final Map<String, int> _openedProfileScore = <String, int>{};
  static final Map<String, SellerProfileEntity> _openedProfilesById =
      <String, SellerProfileEntity>{};
  static final List<String> _recentOpenedProfileIds = <String>[];
  static List<SellerProfileEntity> _topSuggestedUsers = <SellerProfileEntity>[];
  static DateTime? _topSuggestedAt;

  static String _key(String normalizedQuery) =>
      normalizedQuery.toLowerCase().trim();

  static List<SellerProfileEntity>? takeUsers(String q) {
    final k = _key(q);
    if (k.length < 2) return null;
    final t = _usersAt[k];
    if (t == null) return null;
    if (DateTime.now().difference(t) > ttl) {
      _users.remove(k);
      _usersAt.remove(k);
      return null;
    }
    final list = _users[k];
    return list == null ? null : List<SellerProfileEntity>.from(list);
  }

  static void putUsers(String q, List<SellerProfileEntity> items) {
    final k = _key(q);
    if (k.length < 2) return;
    _users[k] = List<SellerProfileEntity>.from(items);
    _usersAt[k] = DateTime.now();
  }

  static List<PostEntity>? takeVideosFirst(String q) {
    final k = _key(q);
    if (k.length < 2) return null;
    final t = _videosAt[k];
    if (t == null) return null;
    if (DateTime.now().difference(t) > ttl) {
      _videosFirstPage.remove(k);
      _videosAt.remove(k);
      return null;
    }
    final list = _videosFirstPage[k];
    return list == null ? null : List<PostEntity>.from(list);
  }

  static void putVideosFirst(String q, List<PostEntity> items) {
    final k = _key(q);
    if (k.length < 2) return;
    _videosFirstPage[k] = List<PostEntity>.from(items);
    _videosAt[k] = DateTime.now();
  }

  static void invalidateQuery(String q) {
    final k = _key(q);
    _users.remove(k);
    _usersAt.remove(k);
    _videosFirstPage.remove(k);
    _videosAt.remove(k);
  }

  static List<String> recentQueries() => List<String>.from(_recentQueries);

  static void rememberQuery(String q) {
    final clean = q.trim();
    if (clean.length < 2) return;
    _recentQueries.removeWhere(
      (e) => e.toLowerCase() == clean.toLowerCase(),
    );
    _recentQueries.insert(0, clean);
    if (_recentQueries.length > 12) {
      _recentQueries.removeRange(12, _recentQueries.length);
    }
  }

  static void removeRecentQuery(String q) {
    _recentQueries.removeWhere(
      (e) => e.toLowerCase() == q.trim().toLowerCase(),
    );
  }

  static void clearRecentQueries() {
    _recentQueries.clear();
  }

  static void rememberOpenedProfile(SellerProfileEntity user) {
    final curr = _openedProfileScore[user.id] ?? 0;
    _openedProfileScore[user.id] = math.min(curr + 1, 24);
    _openedProfilesById[user.id] = user;
    _recentOpenedProfileIds.remove(user.id);
    _recentOpenedProfileIds.insert(0, user.id);
    if (_recentOpenedProfileIds.length > 20) {
      _recentOpenedProfileIds.removeRange(20, _recentOpenedProfileIds.length);
    }
  }

  static int openedProfileScore(String userId) => _openedProfileScore[userId] ?? 0;

  static List<SellerProfileEntity> recentOpenedProfiles() {
    final out = <SellerProfileEntity>[];
    for (final id in _recentOpenedProfileIds) {
      final profile = _openedProfilesById[id];
      if (profile != null) out.add(profile);
      if (out.length >= 8) break;
    }
    return out;
  }

  static List<SellerProfileEntity>? takeTopSuggestedUsers() {
    final t = _topSuggestedAt;
    if (t == null) return null;
    if (DateTime.now().difference(t) > ttl) {
      _topSuggestedUsers = <SellerProfileEntity>[];
      _topSuggestedAt = null;
      return null;
    }
    return List<SellerProfileEntity>.from(_topSuggestedUsers);
  }

  static void putTopSuggestedUsers(List<SellerProfileEntity> users) {
    _topSuggestedUsers = List<SellerProfileEntity>.from(users);
    _topSuggestedAt = DateTime.now();
  }
}

enum _DiscoverSection {
  people,
  videos,
}

/// Глобальный поиск в разделе публикаций: пользователи (имя, био, Telegram)
/// и короткие видео по подписи.
class PublicationDiscoverSearchPage extends StatefulWidget {
  const PublicationDiscoverSearchPage({super.key});

  @override
  State<PublicationDiscoverSearchPage> createState() =>
      _PublicationDiscoverSearchPageState();
}

class _PublicationDiscoverSearchPageState
    extends State<PublicationDiscoverSearchPage> {
  final _focusNode = FocusNode();
  final _controller = TextEditingController();
  final _scrollVideos = ScrollController();

  _DiscoverSection _section = _DiscoverSection.people;

  Timer? _debounce;
  int _peopleGen = 0;
  int _videosGen = 0;

  String _activeQuery = '';

  List<SellerProfileEntity> _people = [];
  List<PostEntity> _videos = [];
  List<String> _querySuggestions = [];
  List<SellerProfileEntity> _similarAccounts = [];
  List<SellerProfileEntity> _topSuggested = [];
  bool _loadingTopSuggested = false;
  List<String> _recentQueriesUi = [];

  bool _loadingPeople = false;
  bool _loadingVideos = false;
  bool _loadingMoreVideos = false;
  bool _hasMoreVideos = true;
  DateTime? _videoCursor;

  static const int _minChars = 2;
  static const int _pageSize = 12;

  @override
  void initState() {
    super.initState();
    _scrollVideos.addListener(_onVideosScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
    _recentQueriesUi = _PublicationDiscoverSearchCache.recentQueries();
    unawaited(_loadTopSuggestedUsers());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollVideos
      ..removeListener(_onVideosScroll)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onVideosScroll() {
    if (!_scrollVideos.hasClients) return;
    if (_section != _DiscoverSection.videos) return;
    final pos = _scrollVideos.position;
    if (pos.maxScrollExtent - pos.pixels > 380) return;
    unawaited(_loadMoreVideos());
  }

  String? get _currentUserId {
    final s = context.read<AuthBloc>().state;
    return s is AuthAuthenticated ? s.user.id : null;
  }

  Future<void> _loadTopSuggestedUsers() async {
    final cached = _PublicationDiscoverSearchCache.takeTopSuggestedUsers();
    if (cached != null) {
      if (!mounted) return;
      setState(() => _topSuggested = _mergeTopAndPersonal(cached));
      return;
    }
    if (mounted) setState(() => _loadingTopSuggested = true);
    try {
      final repo = context.read<ProfileRepository>();
      final verified = await repo.getVerifiedUsers();
      if (!mounted) return;
      final prepared = verified.take(14).toList(growable: false);
      _PublicationDiscoverSearchCache.putTopSuggestedUsers(prepared);
      setState(() {
        _topSuggested = _mergeTopAndPersonal(prepared);
        _loadingTopSuggested = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTopSuggested = false);
    }
  }

  List<SellerProfileEntity> _mergeTopAndPersonal(List<SellerProfileEntity> base) {
    final merged = <String, SellerProfileEntity>{};
    for (final u in _PublicationDiscoverSearchCache.recentOpenedProfiles()) {
      merged[u.id] = u;
      if (merged.length >= 6) break;
    }
    for (final u in base) {
      merged.putIfAbsent(u.id, () => u);
      if (merged.length >= 16) break;
    }
    return merged.values.toList(growable: false);
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), _runSearch);
  }

  Future<void> _runSearch() async {
    final raw = _controller.text.trim();
    if (raw.length < _minChars) {
      setState(() {
        _activeQuery = '';
        _people = [];
        _videos = [];
        _querySuggestions = _PublicationDiscoverSearchCache.recentQueries();
        _recentQueriesUi = _PublicationDiscoverSearchCache.recentQueries();
        _similarAccounts = [];
        _hasMoreVideos = false;
        _videoCursor = null;
        _loadingPeople = false;
        _loadingVideos = false;
      });
      return;
    }

    final peopleGen = ++_peopleGen;
    final videosGen = ++_videosGen;

    setState(() {
      _activeQuery = raw;
      _querySuggestions = _buildQuerySuggestions(raw, _people);
      _hasMoreVideos = true;
      _videoCursor = null;
    });

    final profileRepo = context.read<ProfileRepository>();
    final postRepo = context.read<PostRepository>();
    final uid = _currentUserId;

    final cachedPeople = _PublicationDiscoverSearchCache.takeUsers(raw);
    if (cachedPeople != null && mounted && peopleGen == _peopleGen) {
      final ranked = _rankUsers(raw, cachedPeople);
      setState(() {
        _people = ranked;
        _querySuggestions = _buildQuerySuggestions(raw, ranked);
        _similarAccounts = _buildSimilarAccounts(raw, ranked);
        _loadingPeople = false;
      });
    } else {
      setState(() => _loadingPeople = true);
      try {
        final list = await profileRepo.searchUsers(raw, limit: 40);
        if (!mounted || peopleGen != _peopleGen) return;
        _PublicationDiscoverSearchCache.putUsers(raw, list);
        _PublicationDiscoverSearchCache.rememberQuery(raw);
        final ranked = _rankUsers(raw, list);
        setState(() {
          _recentQueriesUi = _PublicationDiscoverSearchCache.recentQueries();
          _people = ranked;
          _querySuggestions = _buildQuerySuggestions(raw, ranked);
          _similarAccounts = _buildSimilarAccounts(raw, ranked);
          _loadingPeople = false;
        });
      } catch (_) {
        if (!mounted || peopleGen != _peopleGen) return;
        setState(() => _loadingPeople = false);
      }
    }

    final cachedVids = _PublicationDiscoverSearchCache.takeVideosFirst(raw);
    if (cachedVids != null && mounted && videosGen == _videosGen) {
      setState(() {
        _videos = cachedVids;
        _loadingVideos = false;
        _hasMoreVideos = cachedVids.length >= _pageSize;
        _videoCursor =
            cachedVids.isEmpty ? null : cachedVids.last.createdAt;
      });
    } else {
      setState(() => _loadingVideos = true);
      try {
        final list = await postRepo.searchPublicationsByCursor(
          query: raw,
          limit: _pageSize,
          currentUserId: uid,
          videoPublicationsOnly: true,
        );
        if (!mounted || videosGen != _videosGen) return;
        _PublicationDiscoverSearchCache.putVideosFirst(raw, list);
        setState(() {
          _videos = list;
          _loadingVideos = false;
          _hasMoreVideos = list.length >= _pageSize;
          _videoCursor = list.isEmpty ? null : list.last.createdAt;
        });
      } catch (_) {
        if (!mounted || videosGen != _videosGen) return;
        setState(() => _loadingVideos = false);
      }
    }
  }

  String _normalized(String value) => value.toLowerCase().trim();

  int _userScore(SellerProfileEntity user, String query) {
    final q = _normalized(query);
    if (q.isEmpty) return 0;
    final name = _normalized(user.name);
    final bio = _normalized(user.bio ?? '');
    var score = 0;
    if (name == q) score += 220;
    if (name.startsWith(q)) score += 140;
    if (name.contains(' $q')) score += 85;
    if (name.contains(q)) score += 60;
    if (bio.contains(q)) score += 22;
    if (user.isVerified) score += 10;
    score += math.min(18, user.followersCount ~/ 500);
    score += math.min(
      54,
      _PublicationDiscoverSearchCache.openedProfileScore(user.id) * 7,
    );
    return score;
  }

  List<SellerProfileEntity> _rankUsers(
    String query,
    List<SellerProfileEntity> users,
  ) {
    final unique = <String, SellerProfileEntity>{};
    for (final u in users) {
      unique.putIfAbsent(u.id, () => u);
    }
    final ranked = unique.values.toList(growable: false);
    ranked.sort((a, b) {
      final d = _userScore(b, query) - _userScore(a, query);
      if (d != 0) return d;
      return b.followersCount.compareTo(a.followersCount);
    });
    return ranked;
  }

  List<SellerProfileEntity> _buildSimilarAccounts(
    String query,
    List<SellerProfileEntity> ranked,
  ) {
    final q = _normalized(query);
    final out = <SellerProfileEntity>[];
    for (final u in ranked) {
      final name = _normalized(u.name);
      final isExact = name == q;
      if (isExact) continue;
      final score = _userScore(u, query);
      if (score < 70) continue;
      out.add(u);
      if (out.length >= 5) break;
    }
    for (final u in _PublicationDiscoverSearchCache.recentOpenedProfiles()) {
      final name = _normalized(u.name);
      if (!name.contains(q) && !(u.bio ?? '').toLowerCase().contains(q)) {
        continue;
      }
      if (out.any((e) => e.id == u.id)) continue;
      out.add(u);
      if (out.length >= 6) break;
    }
    return out;
  }

  List<String> _buildQuerySuggestions(
    String query,
    List<SellerProfileEntity> rankedUsers,
  ) {
    final raw = query.trim();
    final result = <String>{};
    if (raw.length >= _minChars) result.add(raw);
    final withoutAt = raw.replaceFirst(RegExp(r'^@+'), '');
    if (withoutAt.length >= _minChars) result.add(withoutAt);
    final firstToken = withoutAt.split(RegExp(r'\\s+')).first.trim();
    if (firstToken.length >= _minChars) result.add(firstToken);
    if (withoutAt.length >= _minChars && !withoutAt.startsWith('#')) {
      result.add('#$withoutAt');
    }
    for (final u in rankedUsers.take(6)) {
      final candidate = u.name.trim();
      if (candidate.length >= _minChars) result.add(candidate);
    }
    for (final old in _PublicationDiscoverSearchCache.recentQueries().take(4)) {
      result.add(old);
    }
    for (final p in _PublicationDiscoverSearchCache.recentOpenedProfiles().take(3)) {
      final v = p.name.trim();
      if (v.length >= _minChars) result.add(v);
    }
    return result.take(8).toList(growable: false);
  }

  void _openProfile(SellerProfileEntity user) {
    _PublicationDiscoverSearchCache.rememberOpenedProfile(user);
    context.push('/profile/${user.id}');
  }

  void _removeRecentQuery(String value) {
    _PublicationDiscoverSearchCache.removeRecentQuery(value);
    setState(() {
      _recentQueriesUi = _PublicationDiscoverSearchCache.recentQueries();
      if (_controller.text.trim().isEmpty) {
        _querySuggestions = _recentQueriesUi.take(8).toList(growable: false);
      }
    });
  }

  void _clearRecentQueries() {
    _PublicationDiscoverSearchCache.clearRecentQueries();
    setState(() {
      _recentQueriesUi = const <String>[];
      if (_controller.text.trim().isEmpty) {
        _querySuggestions = const <String>[];
      }
    });
  }

  Future<void> _loadMoreVideos() async {
    if (_activeQuery.length < _minChars) return;
    if (_loadingMoreVideos || !_hasMoreVideos || _videoCursor == null) {
      if (_videos.isNotEmpty && _videoCursor == null) {
        setState(() => _hasMoreVideos = false);
      }
      return;
    }
    final gen = _videosGen;
    setState(() => _loadingMoreVideos = true);
    try {
      final postRepo = context.read<PostRepository>();
      final more = await postRepo.searchPublicationsByCursor(
        query: _activeQuery,
        limit: _pageSize,
        lastCreatedAt: _videoCursor,
        currentUserId: _currentUserId,
        videoPublicationsOnly: true,
      );
      if (!mounted || gen != _videosGen) return;
      if (more.isEmpty) {
        setState(() {
          _hasMoreVideos = false;
          _loadingMoreVideos = false;
        });
        return;
      }
      final seen = _videos.map((p) => p.id).toSet();
      final appended = <PostEntity>[];
      for (final p in more) {
        if (seen.add(p.id)) appended.add(p);
      }
      setState(() {
        _videos = List<PostEntity>.from(_videos)..addAll(appended);
        _videoCursor = more.last.createdAt;
        _hasMoreVideos = more.length >= _pageSize;
        _loadingMoreVideos = false;
      });
    } catch (_) {
      if (!mounted || gen != _videosGen) return;
      setState(() => _loadingMoreVideos = false);
    }
  }

  Future<void> _onRefresh() async {
    final q = _controller.text.trim();
    if (q.length < _minChars) return;
    _PublicationDiscoverSearchCache.invalidateQuery(q);
    await _runSearch();
  }

  String? _thumbUrl(PostEntity p) {
    final urls = p.displayImageUrls;
    if (urls.isNotEmpty) return urls.first;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surfaceContainerHighest.withValues(alpha: 0.35),
              cs.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        'Поиск',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText:
                          'Имя, @telegram или тема видео…',
                      prefixIcon: Icon(Icons.search_rounded, color: cs.primary),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _controller.clear();
                                _scheduleSearch();
                                setState(() {});
                              },
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 14,
                      ),
                    ),
                    onChanged: (_) {
                      setState(() {});
                      _scheduleSearch();
                    },
                    onSubmitted: (_) => _runSearch(),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _SectionChip(
                      label: 'Люди',
                      icon: Icons.people_outline_rounded,
                      selected: _section == _DiscoverSection.people,
                      onTap: () =>
                          setState(() => _section = _DiscoverSection.people),
                    ),
                    const SizedBox(width: 10),
                    _SectionChip(
                      label: 'Видео',
                      icon: Icons.play_circle_outline_rounded,
                      selected: _section == _DiscoverSection.videos,
                      onTap: () =>
                          setState(() => _section = _DiscoverSection.videos),
                    ),
                  ],
                ),
              ),
              if (_querySuggestions.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    itemCount: _querySuggestions.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final text = _querySuggestions[i];
                      return ActionChip(
                        label: Text(
                          text,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                        onPressed: () {
                          _controller.value = TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: text.length,
                            ),
                          );
                          _runSearch();
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
              if (_controller.text.trim().length < _minChars)
                Expanded(child: _buildTopSearchBody(theme, cs))
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: _section == _DiscoverSection.people
                        ? _buildPeopleBody(theme, cs)
                        : _buildVideosBody(theme, cs),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeopleBody(ThemeData theme, ColorScheme cs) {
    if (_loadingPeople && _people.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_people.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: Text(
                'Никого не нашли',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (_similarAccounts.isNotEmpty) ...[
          Text(
            'Похожие аккаунты',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _similarAccounts.length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final u = _similarAccounts[i];
                return _SimilarAccountCard(
                  user: u,
                  onTap: () => _openProfile(u),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < _people.length; i++) ...[
          _UserSearchTile(
            user: _people[i],
            onTap: () => _openProfile(_people[i]),
          ),
          if (i != _people.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildTopSearchBody(ThemeData theme, ColorScheme cs) {
    if (_loadingTopSuggested && _topSuggested.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Рекомендуем',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        if (_topSuggested.isNotEmpty)
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _topSuggested.take(10).length,
              separatorBuilder: (context, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final u = _topSuggested[i];
                return _SimilarAccountCard(
                  user: u,
                  onTap: () => _openProfile(u),
                );
              },
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Начните вводить имя, чтобы увидеть умные результаты.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'Популярные профили',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (_topSuggested.isNotEmpty)
          ..._topSuggested.take(6).map(
            (u) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _UserSearchTile(
                user: u,
                onTap: () => _openProfile(u),
              ),
            ),
          )
        else
          Text(
            'Пока нет рекомендаций.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.outline,
            ),
          ),
        if (_recentQueriesUi.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Недавние поиски',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: _clearRecentQueries,
                child: const Text('Очистить всё'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentQueriesUi.take(12).map((q) {
              return InputChip(
                label: Text(
                  q,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () {
                  _controller.value = TextEditingValue(
                    text: q,
                    selection: TextSelection.collapsed(offset: q.length),
                  );
                  _runSearch();
                  setState(() {});
                },
                onDeleted: () => _removeRecentQuery(q),
              );
            }).toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _buildVideosBody(ThemeData theme, ColorScheme cs) {
    if (_loadingVideos && _videos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.35,
            child: Center(
              child: Text(
                'Нет видео по этому запросу',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return GridView.builder(
      controller: _scrollVideos,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.56,
      ),
      itemCount: _videos.length,
      itemBuilder: (context, i) {
        final p = _videos[i];
        final thumb = _thumbUrl(p);
        return _VideoDiscoverTile(
          post: p,
          thumbUrl: thumb,
          onTap: () => context.push('/post/${p.id}'),
        );
      },
    );
  }
}

class _SectionChip extends StatelessWidget {
  const _SectionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.95)
          : cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 13,
                  color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserSearchTile extends StatelessWidget {
  const _UserSearchTile({
    required this.user,
    required this.onTap,
  });

  final SellerProfileEntity user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CachedAvatar(
                imageUrl: user.avatarUrl,
                radius: 26,
                fallbackText: user.name,
                enableLightboxOnTap: false,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (user.isVerified) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                        ],
                      ],
                    ),
                    if ((user.bio ?? '').trim().isNotEmpty)
                      Text(
                        user.bio!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.outline),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimilarAccountCard extends StatelessWidget {
  const _SimilarAccountCard({
    required this.user,
    required this.onTap,
  });

  final SellerProfileEntity user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 120,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                CachedAvatar(
                  imageUrl: user.avatarUrl,
                  radius: 21,
                  fallbackText: user.name,
                  enableLightboxOnTap: false,
                ),
                const SizedBox(height: 6),
                Text(
                  user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${user.followersCount} подписч.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
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

class _VideoDiscoverTile extends StatelessWidget {
  const _VideoDiscoverTile({
    required this.post,
    required this.thumbUrl,
    required this.onTap,
  });

  final PostEntity post;
  final String? thumbUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = math.max(1, (200 * dpr).round());

    return Material(
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (thumbUrl != null && thumbUrl!.isNotEmpty)
              CachedNetworkImage(
                imageUrl: thumbUrl!,
                fit: BoxFit.cover,
                memCacheWidth: memW,
                memCacheHeight: memW,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                ),
                errorWidget: (_, _, _) => ColoredBox(
                  color: cs.surfaceContainerHighest,
                ),
              )
            else
              ColoredBox(
                color: cs.surfaceContainerHighest,
                child: Icon(Icons.movie_rounded,
                    color: cs.outline, size: 40),
              ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.65),
                  ],
                ),
              ),
            ),
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 44),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Text(
                post.userName ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(blurRadius: 6, color: Colors.black54),
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
