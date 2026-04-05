import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/products/deleted_product_bus.dart';
import '../../../../core/accounts/account_manager.dart';
import '../../../../core/accounts/account_model.dart';
import '../../../../core/storage/multi_account_storage.dart';
import '../../../../core/storage/hidden_posts_storage.dart';
import '../../../../core/storage/chat_story_list_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/formatting/compact_count_format.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/theme/theme_index_notifier.dart';
import '../../../../core/widgets/theme_picker_sheet.dart';
import '../widgets/account_switcher_sheet.dart';
import '../widgets/account_switcher_token_sheet.dart';
import '../widgets/creator_monthly_stats_sheet.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../auth/presentation/pages/login_result.dart';
import '../../../stories/domain/entities/story_group_entity.dart';
import '../../../stories/domain/repositories/stories_repository.dart';
import '../../../stories/presentation/pages/story_viewer_args.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../post/presentation/widgets/post_grid_engagement_overlay.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key, this.initialTabIndex});

  final int? initialTabIndex;

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  static const Duration _warmCacheTtl = Duration(minutes: 30);
  static _MyProfileWarmCache? _warmCache;
  SellerProfileEntity? _profile;
  List<PostEntity> _newsPosts = [];
  List<PostEntity> _publicationPosts = [];
  List<PostEntity> _videoPosts = [];
  bool _loading = true;
  late int _tabIndex;
  bool _updatingAvatar = false;
  bool _isSwitchingAccount = false;
  bool _isLoadingProfileData = false;
  bool _selfVerified = false;
  int _loadRequestId = 0;
  Set<String> _hiddenPostIds = const <String>{};
  bool _autoReloadTriggeredForPublications = false;
  List<StoryGroupEntity> _storyGroups = const [];
  Map<String, bool> _newStoriesByUserId = const {};
  String _myStoryNote = '';
  StreamSubscription<String>? _deletedProductSub;
  supa.RealtimeChannel? _totalLikesChannel;
  late final PageController _profileTabPageController;
  /// Публикации/сетки ещё подгружаются после быстрого показа шапки профиля.
  bool _isFetchingPosts = false;

  @override
  void initState() {
    super.initState();
    var initialTab = widget.initialTabIndex ?? 2;
    if (initialTab > 4) initialTab = 4;
    if (initialTab < 0) initialTab = 0;
    _tabIndex = initialTab;
    _profileTabPageController = PageController(initialPage: _tabIndex);
    final authState = context.read<AuthBloc>().state;
    final uid = authState is AuthAuthenticated ? authState.user.id : null;
    final cache = _warmCache;
    final canUseCache =
        uid != null &&
        cache != null &&
        cache.userId == uid &&
        DateTime.now().difference(cache.createdAt) <= _warmCacheTtl;
    if (canUseCache) {
      _profile = cache.profile;
      _newsPosts = List<PostEntity>.from(cache.newsPosts);
      _publicationPosts = List<PostEntity>.from(cache.publicationPosts);
      _videoPosts = List<PostEntity>.from(cache.videoPosts);
      _storyGroups = List<StoryGroupEntity>.from(cache.storyGroups);
      _newStoriesByUserId = Map<String, bool>.from(cache.newStoriesByUserId);
      _myStoryNote = cache.myStoryNote;
      _loading = false;
    }
    _load(showLoading: !canUseCache);
    if (canUseCache) {
      final uidForLikes = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_attachTotalLikesChannel(uidForLikes));
      });
    }
    unawaited(_loadHiddenPostIds());
    _deletedProductSub = deletedProductIdsStream.listen((_) {
      if (mounted) _load(showLoading: false);
    });
  }

  @override
  void dispose() {
    _profileTabPageController.dispose();
    _deletedProductSub?.cancel();
    unawaited(_detachTotalLikesChannel());
    super.dispose();
  }

  Future<void> _detachTotalLikesChannel() async {
    final ch = _totalLikesChannel;
    _totalLikesChannel = null;
    if (ch != null) {
      await supa.Supabase.instance.client.removeChannel(ch);
    }
  }

  Future<void> _attachTotalLikesChannel(String uid) async {
    await _detachTotalLikesChannel();
    final ch = supa.Supabase.instance.client.channel(
      'profile_total_likes_$uid',
    );
    _totalLikesChannel = ch;
    ch
        .onPostgresChanges(
          event: supa.PostgresChangeEvent.update,
          schema: 'public',
          table: SupabaseConstants.usersTable,
          filter: supa.PostgresChangeFilter(
            type: supa.PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) {
            final raw = payload.newRecord['total_received_post_likes'];
            if (raw == null) return;
            final v = raw is int ? raw : (raw as num).toInt();
            if (!mounted) return;
            setState(() {
              if (_profile != null) {
                _profile = _profile!.copyWith(totalReceivedPostLikes: v);
              }
            });
            final auth = context.read<AuthBloc>().state;
            if (auth is AuthAuthenticated && auth.user.id == uid) {
              _storeWarmCache(uid);
            }
          },
        )
        .subscribe();
  }

  Future<void> _changeAvatar() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы изменить аватар')),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    if (!mounted) return;
    var avatarPath = picked.path;
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 92,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Обрезать аватар',
            toolbarColor: Colors.black,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: true,
            hideBottomControls: false,
            initAspectRatio: CropAspectRatioPreset.square,
          ),
          IOSUiSettings(
            title: 'Обрезать аватар',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            rotateButtonsHidden: false,
            rotateClockwiseButtonHidden: false,
          ),
          if (kIsWeb)
            WebUiSettings(
              context: context,
              presentStyle: WebPresentStyle.dialog,
              size: const CropperSize(width: 380, height: 520),
            ),
        ],
      );
      if (cropped == null) return;
      avatarPath = cropped.path;
    } on MissingPluginException {
      // Тихий fallback: продолжаем с исходным фото без лишних сообщений.
    } on PlatformException catch (_) {
      // Cropper может быть недоступен на части платформ/сборок.
    }
    setState(() => _updatingAvatar = true);
    try {
      final file = File(avatarPath);
      final fileName =
          '${authState.user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      // Храним аватары в отдельном бакете avatars.
      final storageRef = supa.Supabase.instance.client.storage.from(
        SupabaseConstants.bucketAvatars,
      );
      await storageRef.upload(
        fileName,
        file,
        fileOptions: const supa.FileOptions(upsert: true),
      );
      if (!mounted) return;
      final publicUrl = storageRef.getPublicUrl(fileName);

      await context.read<ProfileRepository>().updateProfile(
        userId: authState.user.id,
        avatarUrl: publicUrl,
      );

      if (!mounted) return;
      context.read<AuthBloc>().add(const AuthCheckRequested());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Аватар обновлён')));
    } catch (e, st) {
      if (!mounted) return;
      String message = 'Не удалось обновить аватар: $e';
      if (e is supa.StorageException) {
        message = 'Storage error: ${e.message}';
      } else if (e is supa.PostgrestException) {
        message = 'Postgrest error: ${e.message}';
      }
      // Для отладки можно смотреть полный текст ошибки в консоли.
      debugPrint('Avatar upload error: $e\n$st');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _updatingAvatar = false);
    }
  }

  Future<void> _loadHiddenPostIds() async {
    final hidden = await HiddenPostsStorage.getHiddenPostIds();
    if (!mounted) return;
    setState(() => _hiddenPostIds = hidden);
  }

  bool _isPostHidden(PostEntity post) => _hiddenPostIds.contains(post.id);

  Future<void> _onHidePost(PostEntity post) async {
    await HiddenPostsStorage.hidePost(post.id);
    if (!mounted) return;
    setState(() {
      _hiddenPostIds = {..._hiddenPostIds, post.id};
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Пост скрыт. Теперь он в разделе "Приватные".'),
      ),
    );
  }

  Future<void> _onUnhidePost(PostEntity post) async {
    await HiddenPostsStorage.unhidePost(post.id);
    if (!mounted) return;
    setState(() {
      _hiddenPostIds = {..._hiddenPostIds}..remove(post.id);
    });
  }

  void _storeWarmCache(String uid) {
    _warmCache = _MyProfileWarmCache(
      createdAt: DateTime.now(),
      userId: uid,
      profile: _profile,
      newsPosts: List<PostEntity>.from(_newsPosts),
      publicationPosts: List<PostEntity>.from(_publicationPosts),
      videoPosts: List<PostEntity>.from(_videoPosts),
      storyGroups: List<StoryGroupEntity>.from(_storyGroups),
      newStoriesByUserId: Map<String, bool>.from(_newStoriesByUserId),
      myStoryNote: _myStoryNote,
    );
  }

  Future<void> _load({bool showLoading = true}) async {
    if (_isLoadingProfileData) {
      // Не запускаем параллельные одинаковые загрузки — это дает лишние rebuild и гонки.
      return;
    }
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) {
      setState(() => _loading = false);
      return;
    }
    final uid = state.user.id;
    final requestId = ++_loadRequestId;
    _isLoadingProfileData = true;
    if (showLoading) {
      setState(() => _loading = true);
    }
    try {
      final repo = context.read<ProfileRepository>();
      final postRepo = context.read<PostRepository>();
      final verifiedFuture = _loadSelfVerifiedFlag(uid);
      final profileFuture = repo
          .getSellerProfile(uid)
          .timeout(const Duration(seconds: 10));

      final head = await Future.wait<Object?>([
        verifiedFuture,
        profileFuture,
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      final verifiedFlag = head[0]! as bool;
      final profile = head[1] as SellerProfileEntity?;

      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _profile = profile == null
              ? null
              : SellerProfileEntity(
                  id: profile.id,
                  name: profile.name,
                  avatarUrl: profile.avatarUrl,
                  bio: profile.bio,
                  followersCount: profile.followersCount,
                  followingCount: profile.followingCount,
                  isFollowingByMe: profile.isFollowingByMe,
                  products: profile.products,
                  isVerified: profile.isVerified,
                  instagramUrl: profile.instagramUrl,
                  telegramUsername: profile.telegramUsername,
                  websiteUrl: profile.websiteUrl,
                  totalReceivedPostLikes: profile.totalReceivedPostLikes,
                  officialPageActive: profile.officialPageActive,
                );
          _selfVerified = (profile?.isVerified ?? false) || verifiedFlag;
          _loading = false;
        });
        unawaited(_attachTotalLikesChannel(uid));
      }

      if (mounted && requestId == _loadRequestId) {
        setState(() => _isFetchingPosts = true);
      }

      final postsFuture = postRepo
          .getPostsByUser(uid, currentUserId: uid)
          .timeout(const Duration(seconds: 12));
      final followingFuture =
          repo.getFollowingUsers(uid).timeout(const Duration(seconds: 10));
      final noteFuture = _loadMyStoryNote(uid);

      final bundle = await Future.wait<Object?>([
        postsFuture,
        followingFuture,
        noteFuture,
      ]);
      if (!mounted || requestId != _loadRequestId) return;
      final posts = bundle[0]! as List<PostEntity>;
      final followingCount =
          (bundle[1]! as List<SellerProfileEntity>).length;
      final myStoryNote = bundle[2]! as String;

      final newsPosts = posts
          .where(
            (p) => p.kind.trim().toLowerCase() == 'news' && !_isVideoPost(p),
          )
          .toList(growable: false);
      final publicationPosts = posts
          .where(
            (p) =>
                p.kind.trim().toLowerCase() == 'publication' &&
                !_isVideoPost(p),
          )
          .toList(growable: false);
      final videoPosts = posts.where(_isVideoPost).toList(growable: false);

      if (mounted && requestId == _loadRequestId) {
        setState(() {
          _profile = _profile == null
              ? null
              : SellerProfileEntity(
                  id: _profile!.id,
                  name: _profile!.name,
                  avatarUrl: _profile!.avatarUrl,
                  bio: _profile!.bio,
                  followersCount: _profile!.followersCount,
                  followingCount: followingCount,
                  isFollowingByMe: _profile!.isFollowingByMe,
                  products: _profile!.products,
                  isVerified: _profile!.isVerified,
                  instagramUrl: _profile!.instagramUrl,
                  telegramUsername: _profile!.telegramUsername,
                  websiteUrl: _profile!.websiteUrl,
                  totalReceivedPostLikes: _profile!.totalReceivedPostLikes,
                  officialPageActive: _profile!.officialPageActive,
                );
          _newsPosts = newsPosts;
          _publicationPosts = publicationPosts;
          _videoPosts = videoPosts;
          _myStoryNote = myStoryNote;
          _isFetchingPosts = false;
          if (publicationPosts.isNotEmpty) {
            _autoReloadTriggeredForPublications = false;
          }
        });
        _storeWarmCache(uid);
      }

      unawaited(_loadProfileStories(uid, showLoading: false));

      if (publicationPosts.isEmpty) {
        unawaited(_backfillPublicationsFromSearch(uid, requestId));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _isFetchingPosts = false;
        });
      }
    } finally {
      if (requestId == _loadRequestId) {
        _isLoadingProfileData = false;
      }
    }
  }

  /// Тяжёлый fallback из ленты публикаций — только в фоне, не блокирует первый кадр.
  Future<void> _backfillPublicationsFromSearch(
    String uid,
    int requestId,
  ) async {
    try {
      final postRepo = context.read<PostRepository>();
      final feed = await postRepo
          .searchPublicationsByCursor(
            query: '',
            limit: 100,
            currentUserId: uid,
          )
          .timeout(const Duration(seconds: 12));
      if (!mounted || requestId != _loadRequestId) return;
      final mine = feed
          .where((p) => p.userId == uid && !_isVideoPost(p))
          .toList(growable: false);
      if (mine.isEmpty) return;
      setState(() {
        _publicationPosts = mine;
        _autoReloadTriggeredForPublications = false;
      });
      _storeWarmCache(uid);
    } catch (_) {}
  }

  Future<void> _openBioEditor() async {
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) return;
    final repo = context.read<ProfileRepository>();
    final currentBio = (_profile?.bio ?? state.user.bio ?? '').trim();
    final controller = TextEditingController(text: currentBio);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Редактировать био',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                maxLength: 120,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Био профиля',
                  hintText: 'Расскажите о себе',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, 'delete'),
                      child: const Text('Удалить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'save'),
                      child: const Text('Сохранить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (action == null) return;
    try {
      final nextBio = action == 'save' ? controller.text.trim() : '';
      await repo.updateProfile(
        userId: state.user.id,
        bio: nextBio,
      );
      if (!mounted) return;
      setState(() {
        _profile = _profile?.copyWith(bio: nextBio);
      });
      _storeWarmCache(state.user.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось обновить био')),
      );
    }
  }

  Future<String> _loadMyStoryNote(String uid) async {
    try {
      final me = await supa.Supabase.instance.client
          .from(SupabaseConstants.userStorySettingsTable)
          .select('story_note')
          .eq('user_id', uid)
          .maybeSingle();
      return (me?['story_note'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }

  Future<bool> _loadSelfVerifiedFlag(String uid) async {
    try {
      final row = await supa.Supabase.instance.client
          .from(SupabaseConstants.usersTable)
          .select('is_verified, official_page_active, seller_verified_store')
          .eq('id', uid)
          .maybeSingle();
      return (row?['is_verified'] as bool? ?? false) ||
          (row?['official_page_active'] as bool? ?? false) ||
          (row?['seller_verified_store'] as bool? ?? false);
    } on supa.PostgrestException catch (_) {
      final row = await supa.Supabase.instance.client
          .from(SupabaseConstants.usersTable)
          .select('is_verified')
          .eq('id', uid)
          .maybeSingle();
      return row?['is_verified'] as bool? ?? false;
    }
  }

  Future<void> _loadProfileStories(
    String uid, {
    bool showLoading = false,
  }) async {
    if (showLoading) {
      setState(() => _loading = true);
    }
    try {
      final storiesRepo = context.read<StoriesRepository>();
      final authForStories = context.read<AuthBloc>().state;
      final allGroups = await storiesRepo.getStoriesGroupedByUser();
      if (!mounted) return;
      final ownStories = await storiesRepo.getStoriesByUser(uid);
      final peerIds = <String>{};
      try {
        final rows = await supa.Supabase.instance.client
            .from(SupabaseConstants.messagesTable)
            .select('sender_id, receiver_id')
            .or('sender_id.eq.$uid,receiver_id.eq.$uid');
        for (final row in (rows as List<dynamic>)) {
          final map = row as Map<String, dynamic>;
          final senderId = map['sender_id'] as String?;
          final receiverId = map['receiver_id'] as String?;
          if (senderId == null || receiverId == null) continue;
          if (senderId == uid) {
            peerIds.add(receiverId);
          } else if (receiverId == uid) {
            peerIds.add(senderId);
          }
        }
      } catch (_) {
        // Даже если чат-список недоступен, собственные сторис все равно покажем.
      }
      if (!mounted) return;
      var groups = allGroups
          .where((g) => g.stories.isNotEmpty)
          .where((g) => g.userId == uid || peerIds.contains(g.userId))
          .toList(growable: false);
      final aliveOwnStories = ownStories
          .where((s) => s.expiresAt.isAfter(DateTime.now()))
          .toList(growable: false);
      if (aliveOwnStories.isNotEmpty && groups.every((g) => g.userId != uid)) {
        final auth = authForStories is AuthAuthenticated
            ? authForStories
            : null;
        groups = [
          StoryGroupEntity(
            userId: uid,
            stories: aliveOwnStories,
            userName: auth != null
                ? (auth.user.username ?? auth.user.name ?? auth.user.email)
                : 'Вы',
            userAvatarUrl: auth?.user.avatarUrl,
          ),
          ...groups,
        ];
      }
      if (!mounted) return;
      final seenStorage = context.read<ChatStoryListStorage>();
      final nextMap = <String, bool>{};
      for (final g in groups) {
        final latestStoryAt = g.firstStory.createdAt;
        final lastSeenAt = seenStorage.getLastSeenAt(g.userId);
        nextMap[g.userId] =
            lastSeenAt == null || latestStoryAt.isAfter(lastSeenAt);
      }
      if (!mounted) return;
      final hasStoriesChanged =
          !_sameStoryGroups(_storyGroups, groups) ||
          !_sameStoryFlags(_newStoriesByUserId, nextMap);
      if (hasStoriesChanged) {
        setState(() {
          _storyGroups = groups;
          _newStoriesByUserId = nextMap;
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
      _storeWarmCache(uid);
    } catch (_) {
      if (!mounted) return;
      if (showLoading) {
        setState(() => _loading = false);
      }
    }
  }

  bool _sameStoryGroups(List<StoryGroupEntity> a, List<StoryGroupEntity> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].userId != b[i].userId) return false;
      final aFirst = a[i].stories.isNotEmpty ? a[i].stories.first.id : '';
      final bFirst = b[i].stories.isNotEmpty ? b[i].stories.first.id : '';
      if (aFirst != bFirst) return false;
      if (a[i].stories.length != b[i].stories.length) return false;
    }
    return true;
  }

  bool _sameStoryFlags(Map<String, bool> a, Map<String, bool> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _showAddChoice() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Добавить',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.shopping_bag_outlined, size: 28),
                title: const Text('Товар'),
                subtitle: const Text('Продать вещь на маркете'),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/add-product');
                },
              ),
              ListTile(
                leading: const Icon(Icons.article_outlined, size: 28),
                title: const Text('Публикация'),
                subtitle: const Text(
                  'Фото или короткое видео в ленту публикаций',
                ),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_openCreateNewsAndRefresh());
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_outline_rounded, size: 28),
                title: const Text('Публикация'),
                subtitle: const Text('Личный пост в публикации профиля'),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(_openCreatePublicationAndRefresh(videoMode: false));
                },
              ),
            ],
          ),
        ),
      ),
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
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_openCreatePublicationAndRefresh(videoMode: false));
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Сторис'),
              onTap: () {
                Navigator.pop(sheetContext);
                context.push('/add-story');
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Видео'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_openCreatePublicationAndRefresh(videoMode: true));
              },
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Публикация'),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_openCreateNewsAndRefresh());
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
    if (!_loading &&
        _tabIndex == 2 &&
        _publicationPosts.isEmpty &&
        !_autoReloadTriggeredForPublications) {
      _autoReloadTriggeredForPublications = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load();
      });
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _showQuickCreateMenu,
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: GestureDetector(
          onTap: () {
            final state = context.read<AuthBloc>().state;
            if (state is! AuthAuthenticated) return;
            _showAccountSwitcher(context, state.user);
          },
          child: Builder(
            builder: (context) {
              final state = context.read<AuthBloc>().state;
              if (state is! AuthAuthenticated) {
                return const Text(
                  'Профиль',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }
              final user = state.user;
              final title = (user.username != null && user.username!.isNotEmpty)
                  ? user.username!
                  : user.email;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              );
            },
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'История баттлов',
            icon: const Icon(Icons.emoji_events_outlined, size: 24),
            onPressed: () => context.push('/live-battle-history'),
          ),
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 26),
            onPressed: () {
              // Меню: темки, избранное, настройки, выйти
              _showProfileMenu(context);
            },
          ),
        ],
      ),
      body: BlocListener<AuthBloc, AuthState>(
        listenWhen: (prev, curr) =>
            curr is AuthAuthenticated &&
            (prev is! AuthAuthenticated || prev.user.id != curr.user.id),
        listener: (context, state) {
          if (state is! AuthAuthenticated) return;
          _warmCache = null;
          setState(() {
            _profile = null;
            _newsPosts = [];
            _publicationPosts = [];
            _videoPosts = [];
            _storyGroups = [];
            _newStoriesByUserId = {};
            _myStoryNote = '';
            _loading = false;
            _autoReloadTriggeredForPublications = false;
          });
          unawaited(_load(showLoading: false));
        },
        child: BlocBuilder<AuthBloc, AuthState>(
          buildWhen: (prev, curr) {
            bool authed(AuthState s) => s is AuthAuthenticated;
            if (!authed(prev) && !authed(curr)) return false;
            if (authed(prev) != authed(curr)) return true;
            final p = (prev as AuthAuthenticated).user;
            final c = (curr as AuthAuthenticated).user;
            return p.id != c.id ||
                p.avatarUrl != c.avatarUrl ||
                p.name != c.name ||
                p.username != c.username ||
                p.email != c.email;
          },
          builder: (context, state) {
            final user = state is AuthAuthenticated ? state.user : null;
            if (user == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Войдите в аккаунт'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.push('/login'),
                      child: const Text('Войти'),
                    ),
                  ],
                ),
              );
            }
            if (_loading && _profile == null && !_isFetchingPosts) {
              return const Center(child: CircularProgressIndicator());
            }
            final ownGroup = _storyGroups.cast<StoryGroupEntity?>().firstWhere(
              (g) => g?.userId == user.id,
              orElse: () => null,
            );
            final visibleNewsPosts = _newsPosts
                .where((p) => !_isPostHidden(p))
                .toList(growable: false);
            final visiblePublicationPosts = _publicationPosts
                .where((p) => !_isPostHidden(p))
                .toList(growable: false);
            final visibleVideoPosts = _videoPosts
                .where((p) => !_isPostHidden(p))
                .toList(growable: false);
            final privatePosts =
                [..._newsPosts, ..._publicationPosts, ..._videoPosts]
                    .where(_isPostHidden)
                    .fold<Map<String, PostEntity>>(<String, PostEntity>{}, (
                      acc,
                      p,
                    ) {
                      acc[p.id] = p;
                      return acc;
                    })
                    .values
                    .toList(growable: false)
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            return _ProfileContent(
              user: user,
              profile: _profile,
              selfVerified: _selfVerified,
              newsPosts: visibleNewsPosts,
              publicationPosts: visiblePublicationPosts,
              videoPosts: visibleVideoPosts,
              privatePosts: privatePosts,
              tabIndex: _tabIndex,
              tabPageController: _profileTabPageController,
              onProfileTabSwipe: (i) {
                if (_tabIndex != i) setState(() => _tabIndex = i);
              },
              onTabChipTap: (i) {
                setState(() => _tabIndex = i);
                if (_profileTabPageController.hasClients) {
                  _profileTabPageController.jumpToPage(i);
                }
              },
              showPostsProgress: _isFetchingPosts,
              onRefresh: _load,
              onAddTap: _showAddChoice,
              onOpenAccountSwitcher: () => _showAccountSwitcher(context, user),
              onEditBio: _openBioEditor,
              onHidePost: _onHidePost,
              onUnhidePost: _onUnhidePost,
              onAvatarTap: _changeAvatar,
              updatingAvatar: _updatingAvatar,
              ownStoryGroup: ownGroup,
              officialPageActive: _profile?.officialPageActive ?? false,
              onOpenCreatorStats: () => showCreatorMonthlyStatsSheet(context),
              myStoryNote: _myStoryNote,
              onCreateNews: _openCreateNewsAndRefresh,
              onCreatePublication: () =>
                  _openCreatePublicationAndRefresh(videoMode: false),
              onCreateVideo: () =>
                  _openCreatePublicationAndRefresh(videoMode: true),
              onOpenOwnStory: () async {
                if (ownGroup == null) {
                  await context.push('/add-story');
                  if (!context.mounted) return;
                  await _loadProfileStories(user.id);
                  return;
                }
                await context.push(
                  '/stories',
                  extra: StoryViewerArgs(
                    groups: [ownGroup],
                    initialGroupIndex: 0,
                  ),
                );
                if (!context.mounted) return;
                try {
                  final latestStoryAt = ownGroup.firstStory.createdAt;
                  await context.read<ChatStoryListStorage>().setLastSeenAt(
                    ownGroup.userId,
                    latestStoryAt,
                  );
                  if (!context.mounted) return;
                  setState(() {
                    _newStoriesByUserId = {
                      ..._newStoriesByUserId,
                      ownGroup.userId: false,
                    };
                  });
                } catch (_) {}
                if (!context.mounted) return;
                await _loadProfileStories(user.id);
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _openCreateNewsAndRefresh() async {
    await context.push('/add-news');
    if (!mounted) return;
    await _load(showLoading: false);
  }

  Future<void> _openCreatePublicationAndRefresh({
    required bool videoMode,
  }) async {
    final route = videoMode ? '/add-publication?video=1' : '/add-publication';
    final result = await context.push(route);
    if (!mounted) return;
    if (result is PostEntity) {
      setState(() {
        final hasVideo = _isVideoPost(result);
        if (hasVideo) {
          _videoPosts = [result, ..._videoPosts];
          _tabIndex = 3;
          if (_profileTabPageController.hasClients) {
            _profileTabPageController.jumpToPage(3);
          }
        } else {
          _publicationPosts = [result, ..._publicationPosts];
        }
      });
      final authState = context.read<AuthBloc>().state;
      if (authState is AuthAuthenticated) {
        _storeWarmCache(authState.user.id);
      }
      return;
    }
    await _load(showLoading: false);
  }

  bool _isVideoPost(PostEntity post) {
    final videoUrl = (post.videoUrl ?? '').trim().toLowerCase();
    if (videoUrl.isNotEmpty) return true;
    final imageUrl = post.imageUrl.trim().toLowerCase();
    if (imageUrl.isEmpty) return false;
    return imageUrl.contains('/videos/') ||
        imageUrl.endsWith('.mp4') ||
        imageUrl.endsWith('.mov') ||
        imageUrl.endsWith('.m4v') ||
        imageUrl.endsWith('.webm') ||
        imageUrl.endsWith('.m3u8');
  }

  void _showAccountSwitcher(BuildContext context, AppUser currentUser) {
    final rootContext = context;
    final accountStorage = rootContext.read<MultiAccountStorage>();
    final accountManager = rootContext.read<AccountManager>();
    final savedAccounts = accountStorage.getAccounts();
    // Один Future на открытие шита — не создаём новый при каждом rebuild.
    final accountsFuture = accountManager.loadAccounts();
    showModalBottomSheet<void>(
      context: rootContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => FutureBuilder<List<AccountModel>>(
          future: accountsFuture,
          builder: (sheetContext, snapshot) {
            final accounts = snapshot.data ?? const [];
            final active = accountManager.activeAccount;
            if (accounts.isEmpty) {
              // Fallback на старый переключатель, если ещё нет токен-аккаунтов.
              return AccountSwitcherSheet(
                scrollController: scrollController,
                currentUser: currentUser,
                savedAccounts: savedAccounts,
                onAddAccount: () async {
                  await accountStorage.addAccount(
                    SavedAccount(
                      id: currentUser.id,
                      email: currentUser.email,
                      name: currentUser.name,
                      avatarUrl: currentUser.avatarUrl,
                    ),
                  );
                  if (!rootContext.mounted) return;
                  final result = await rootContext.push<dynamic>(
                    '/login',
                    extra: {'addAccount': true},
                  );
                  if (!rootContext.mounted) return;
                  if (result is LoginResult) {
                    if (result.password != null &&
                        result.password!.isNotEmpty) {
                      accountStorage.savePasswordImmediate(
                        result.userId,
                        result.email,
                        result.password!,
                      );
                    }
                    await accountStorage.addAccount(
                      SavedAccount(
                        id: result.userId,
                        email: result.email,
                        name: result.name,
                        avatarUrl: result.avatarUrl,
                      ),
                      password: result.password,
                    );
                    setState(() {});
                  }
                },
                onSwitchAccount: (account, closeSheet) async {
                  if (_isSwitchingAccount) return;
                  _isSwitchingAccount = true;
                  closeSheet();
                  String? password;
                  try {
                    password = await accountStorage.getPassword(
                      account.id,
                      email: account.email,
                    );
                  } catch (_) {
                    password = null;
                  }
                  if (password == null || password.isEmpty) {
                    if (!rootContext.mounted) {
                      _isSwitchingAccount = false;
                      return;
                    }
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      const SnackBar(
                        content: Text('Введите пароль для переключения'),
                      ),
                    );
                    await rootContext.push<void>(
                      '/login',
                      extra: {'email': account.email},
                    );
                    if (rootContext.mounted) {
                      setState(() => _isSwitchingAccount = false);
                    }
                    return;
                  }
                  if (!rootContext.mounted) {
                    _isSwitchingAccount = false;
                    return;
                  }
                  rootContext.read<AuthBloc>().add(
                    AuthSwitchToAccountRequested(
                      email: account.email,
                      password: password,
                    ),
                  );
                  setState(() => _isSwitchingAccount = false);
                },
              );
            }
            return AccountSwitcherTokenSheet(
              scrollController: scrollController,
              activeAccount: active,
              accounts: accounts,
              savedAccounts: savedAccounts,
              onAddAccount: () async {
                await accountStorage.addAccount(
                  SavedAccount(
                    id: currentUser.id,
                    email: currentUser.email,
                    name: currentUser.name,
                    avatarUrl: currentUser.avatarUrl,
                  ),
                );
                if (!rootContext.mounted) return;
                final result = await rootContext.push<dynamic>(
                  '/login',
                  extra: {'addAccount': true},
                );
                if (!rootContext.mounted) return;
                if (result is LoginResult) {
                  if (result.password != null && result.password!.isNotEmpty) {
                    accountStorage.savePasswordImmediate(
                      result.userId,
                      result.email,
                      result.password!,
                    );
                  }
                  await accountStorage.addAccount(
                    SavedAccount(
                      id: result.userId,
                      email: result.email,
                      name: result.name,
                      avatarUrl: result.avatarUrl,
                    ),
                    password: result.password,
                  );
                  setState(() {});
                }
              },
              onSelectAccount: (account) async {
                if (_isSwitchingAccount) return;
                _isSwitchingAccount = true;
                Navigator.of(sheetContext).pop();
                try {
                  await accountManager.switchAccount(account);
                } on supa.AuthApiException catch (e) {
                  final code = e.code ?? '';
                  final message = e.message.toLowerCase();
                  final isInvalidRefreshToken =
                      code == 'refresh_token_not_found' ||
                      message.contains('invalid refresh token');
                  if (isInvalidRefreshToken) {
                    if (!rootContext.mounted) {
                      _isSwitchingAccount = false;
                      return;
                    }
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Сессия аккаунта устарела. Войдите заново.',
                        ),
                      ),
                    );
                    await rootContext.push<void>(
                      '/login',
                      extra: {'email': account.email},
                    );
                    if (rootContext.mounted) {
                      setState(() => _isSwitchingAccount = false);
                    }
                    return;
                  }
                  rethrow;
                }
                if (!rootContext.mounted) {
                  _isSwitchingAccount = false;
                  return;
                }
                rootContext.read<AuthBloc>().add(const AuthCheckRequested());
                setState(() => _isSwitchingAccount = false);
              },
            );
          },
        ),
      ),
    );
  }

  void _showThemePicker(
    BuildContext context, {
    ThemeIndexNotifier? themeNotifier,
  }) {
    final notifier = themeNotifier ?? context.read<ThemeIndexNotifier>();
    final currentIndex = notifier.value;
    showThemePickerSheet(
      context,
      currentIndex: currentIndex,
      onSelect: (index) => notifier.setIndex(index),
      onAddCustom: () async {
        final picker = ImagePicker();
        final xFile = await picker.pickImage(source: ImageSource.gallery);
        if (kDebugMode) {
          debugPrint(
            '[Темки] pickImage result: ${xFile != null ? "ok ${xFile.path}" : "null"}',
          );
        }
        if (xFile == null || !context.mounted) return;
        final bytes = await xFile.readAsBytes();
        if (kDebugMode) {
          debugPrint('[Темки] readAsBytes: ${bytes.length} bytes');
        }
        if (!context.mounted) return;
        await notifier.setCustomThemeFromImageBytes(bytes);
        if (kDebugMode) {
          debugPrint('[Темки] setCustomThemeFromImageBytes done');
        }
      },
    );
  }

  void _showThemePickerWithNotifier(
    BuildContext context,
    ThemeIndexNotifier notifier,
  ) {
    _showThemePicker(context, themeNotifier: notifier);
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
            // ── Кошелёк Qarmet — первый и особенный ──────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: GestureDetector(
                onTap: () {
                  Navigator.pop(context);
                  context.push('/qarmet-wallet');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F2027),
                        Color(0xFF203A43),
                        Color(0xFF2C5364),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF203A43).withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.account_balance_wallet_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Кошелёк Qarmet',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'Баланс · пополнение · продвижение',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.7),
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
            // ── Остальные пункты ─────────────────────────────────────────
            ListTile(
              leading: const Icon(Icons.touch_app_rounded),
              title: const Text('Тап судьбы 🔥'),
              onTap: () {
                Navigator.pop(context);
                context.push('/tap-game');
              },
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Темки'),
              onTap: () {
                final themeNotifier = context.read<ThemeIndexNotifier>();
                final navigator = Navigator.of(context);
                navigator.pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final overlayContext = navigator.context;
                  if (overlayContext.mounted) {
                    _showThemePickerWithNotifier(overlayContext, themeNotifier);
                  }
                });
              },
            ),
            ListTile(
              leading: const Icon(Icons.favorite_border),
              title: const Text('Избранное'),
              onTap: () {
                Navigator.pop(context);
                context.push('/favorites');
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border_rounded),
              title: const Text('Сохранённые публикации'),
              onTap: () {
                Navigator.pop(context);
                context.push('/saved-publications');
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Редактировать профиль'),
              onTap: () {
                Navigator.pop(context);
                context.push('/edit-profile');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Настройки'),
              onTap: () {
                Navigator.pop(context);
                context.push('/profile/settings');
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Выйти',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                final navigator = Navigator.of(context);
                final rootContext = navigator.context;
                final authState = rootContext.read<AuthBloc>().state;
                if (authState is AuthAuthenticated) {
                  final userId = authState.user.id;
                  try {
                    rootContext.read<AccountManager>().removeAccount(userId);
                  } catch (_) {}
                  try {
                    rootContext.read<MultiAccountStorage>().removeAccount(
                      userId,
                    );
                  } catch (_) {}
                }
                navigator.pop();
                rootContext.read<AuthBloc>().add(const AuthSignOutRequested());
              },
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.user,
    required this.profile,
    required this.selfVerified,
    required this.newsPosts,
    required this.publicationPosts,
    required this.videoPosts,
    required this.privatePosts,
    required this.tabIndex,
    required this.tabPageController,
    required this.onProfileTabSwipe,
    required this.onTabChipTap,
    required this.showPostsProgress,
    required this.onRefresh,
    required this.onAddTap,
    required this.onOpenAccountSwitcher,
    required this.onEditBio,
    required this.onHidePost,
    required this.onUnhidePost,
    required this.onAvatarTap,
    required this.updatingAvatar,
    required this.ownStoryGroup,
    required this.officialPageActive,
    required this.onOpenCreatorStats,
    required this.myStoryNote,
    required this.onCreateNews,
    required this.onCreatePublication,
    required this.onCreateVideo,
    required this.onOpenOwnStory,
  });

  final AppUser user;
  final SellerProfileEntity? profile;
  final bool selfVerified;
  final List<PostEntity> newsPosts;
  final List<PostEntity> publicationPosts;
  final List<PostEntity> videoPosts;
  final List<PostEntity> privatePosts;
  final int tabIndex;
  final PageController tabPageController;
  final ValueChanged<int> onProfileTabSwipe;
  final ValueChanged<int> onTabChipTap;
  final bool showPostsProgress;
  final VoidCallback onRefresh;
  final VoidCallback onAddTap;
  final VoidCallback onOpenAccountSwitcher;
  final Future<void> Function() onEditBio;
  final Future<void> Function(PostEntity post) onHidePost;
  final Future<void> Function(PostEntity post) onUnhidePost;
  final VoidCallback onAvatarTap;
  final bool updatingAvatar;
  final StoryGroupEntity? ownStoryGroup;
  final bool officialPageActive;
  final VoidCallback onOpenCreatorStats;
  final String myStoryNote;
  final Future<void> Function() onCreateNews;
  final Future<void> Function() onCreatePublication;
  final Future<void> Function() onCreateVideo;
  final Future<void> Function()? onOpenOwnStory;

  int get _publicationsCount =>
      (profile?.products.length ?? 0) +
      newsPosts.length +
      publicationPosts.length;

  String? _normalizeInstagramUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final handle = value.replaceFirst('@', '');
    if (handle.isEmpty) return null;
    return 'https://instagram.com/$handle';
  }

  String? _normalizeTelegramUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    final handle = value.replaceFirst('@', '');
    if (handle.isEmpty) return null;
    return 'https://t.me/$handle';
  }

  String? _normalizeWebsiteUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    return 'https://$value';
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 20),
              child: DecoratedBox(
                decoration: ThemedContentSurface.profileCardDecoration(
                  radius: ThemedContentSurface.profileUnifiedRadius,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    ThemedContentSurface.profileUnifiedRadius,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFE8EDF5),
                              Color(0xFFF8FAFD),
                              Colors.white,
                            ],
                            stops: [0.0, 0.45, 1.0],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 26, 20, 18),
                          child: Column(
                            children: [
                              Stack(
                                alignment: Alignment.bottomRight,
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.18),
                                          blurRadius: 20,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: Container(
                                      padding: EdgeInsets.all(
                                        officialPageActive ? 3.5 : 3,
                                      ),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: officialPageActive
                                            ? const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xFFFFF8E1),
                                                  Color(0xFFFFE082),
                                                  Color(0xFFFFC107),
                                                  Color(0xFFFFA000),
                                                  Color(0xFFFF8F00),
                                                ],
                                              )
                                            : (ownStoryGroup != null
                                                ? const LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Color(0xFFFEDA75),
                                                      Color(0xFFFA7E1E),
                                                      Color(0xFFD62976),
                                                      Color(0xFF962FBF),
                                                      Color(0xFF4F5BD5),
                                                    ],
                                                  )
                                                : null),
                                        color: (!officialPageActive &&
                                                ownStoryGroup == null)
                                            ? Colors.white
                                            : null,
                                        boxShadow: officialPageActive
                                            ? [
                                                BoxShadow(
                                                  color: const Color(0xFFFFB300)
                                                      .withValues(alpha: 0.35),
                                                  blurRadius: 14,
                                                  spreadRadius: 0,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: GestureDetector(
                                        onTap: () async {
                                          if (onOpenOwnStory != null) {
                                            await onOpenOwnStory!.call();
                                            return;
                                          }
                                          final imageUrl =
                                              user.avatarUrl ??
                                              profile?.avatarUrl;
                                          if (imageUrl == null ||
                                              imageUrl.isEmpty) {
                                            return;
                                          }
                                          showDialog<void>(
                                            context: context,
                                            builder: (ctx) => Dialog(
                                              backgroundColor: Colors.black,
                                              insetPadding:
                                                  const EdgeInsets.all(24),
                                              child: AspectRatio(
                                                aspectRatio: 1,
                                                child: InteractiveViewer(
                                                  child: CachedNetworkImage(
                                                    imageUrl: imageUrl,
                                                    fit: BoxFit.cover,
                                                    fadeInDuration:
                                                        Duration.zero,
                                                    fadeOutDuration:
                                                        Duration.zero,
                                                    placeholder: (c, u) =>
                                                        const ColoredBox(
                                                          color: Colors.black26,
                                                        ),
                                                    errorWidget: (c, u, e) =>
                                                        const ColoredBox(
                                                          color: Colors.black54,
                                                        ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                        child: CachedAvatar(
                                          imageUrl: (() {
                                            final base =
                                                user.avatarUrl ??
                                                profile?.avatarUrl;
                                            if (base == null || base.isEmpty) {
                                              return null;
                                            }
                                            return '$base?uid=${user.id}';
                                          })(),
                                          radius: 46,
                                          fallbackText: user.name ?? user.email,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: GestureDetector(
                                      onTap: updatingAvatar
                                          ? null
                                          : onAvatarTap,
                                      child: Container(
                                        width: 26,
                                        height: 26,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.12,
                                              ),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: updatingAvatar
                                            ? const Padding(
                                                padding: EdgeInsets.all(4),
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(Colors.white),
                                                ),
                                              )
                                            : const Icon(
                                                Icons.add_rounded,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (ownStoryGroup != null) ...[
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => onOpenOwnStory?.call(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFFFEDA75),
                                          Color(0xFFFA7E1E),
                                          Color(0xFFD62976),
                                          Color(0xFF4F5BD5),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      'Ваша сторис · смотреть',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (officialPageActive) ...[
                                const SizedBox(height: 12),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      HapticFeedback.lightImpact();
                                      onOpenCreatorStats();
                                    },
                                    borderRadius: BorderRadius.circular(18),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        gradient: LinearGradient(
                                          colors: [
                                            const Color(0xFFFFF8E1)
                                                .withValues(alpha: 0.9),
                                            const Color(0xFFFFECB3)
                                                .withValues(alpha: 0.65),
                                          ],
                                        ),
                                        border: Border.all(
                                          color: const Color(0xFFD4AF37)
                                              .withValues(alpha: 0.55),
                                          width: 1.2,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFFFFB300)
                                                .withValues(alpha: 0.18),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                gradient: LinearGradient(
                                                  colors: [
                                                    const Color(0xFFFFD54F),
                                                    const Color(0xFFFFA000)
                                                        .withValues(alpha: 0.9),
                                                  ],
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.insights_rounded,
                                                size: 22,
                                                color: Color(0xFF3E2723),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Статистика профиля',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: const Color(
                                                            0xFF3E2723,
                                                          ),
                                                        ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'Просмотры, взаимодействия, подписчики и контент за 30 дней',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: const Color(
                                                            0xFF5D4037,
                                                          ).withValues(
                                                            alpha: 0.85,
                                                          ),
                                                          height: 1.25,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              Icons.chevron_right_rounded,
                                              color: const Color(0xFF795548)
                                                  .withValues(alpha: 0.7),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    onOpenAccountSwitcher();
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                      horizontal: 8,
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                (user.username != null &&
                                                        user.username!.isNotEmpty)
                                                    ? '@${user.username}'
                                                    : user.email,
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: -0.3,
                                                      color: ThemedContentSurface
                                                          .profileTextPrimary,
                                                    ),
                                              ),
                                            ),
                                            if ((profile?.isVerified ?? selfVerified)) ...[
                                              const SizedBox(width: 6),
                                              const VerifiedBadge(size: 18),
                                            ],
                                          ],
                                        ),
                                        if (user.name != null &&
                                            user.name!.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  user.name!,
                                                  textAlign: TextAlign.center,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge
                                                      ?.copyWith(
                                                        color: ThemedContentSurface
                                                            .profileTextSecondary,
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => unawaited(onEditBio()),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F5F9),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                (user.bio ?? profile?.bio ?? '').isNotEmpty
                                    ? (user.bio ?? profile?.bio ?? '')
                                    : 'Нажмите, чтобы добавить био',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: ThemedContentSurface
                                          .profileTextSecondary,
                                      height: 1.45,
                                    ),
                              ),
                            ),
                          ),
                      ),
                      if (_normalizeInstagramUrl(profile?.instagramUrl) != null ||
                          _normalizeTelegramUrl(profile?.telegramUsername) != null ||
                          _normalizeWebsiteUrl(profile?.websiteUrl) != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_normalizeInstagramUrl(profile?.instagramUrl) case final instagram?)
                                _ProfileSocialChip(
                                  icon: Icons.camera_alt_outlined,
                                  label: 'Instagram',
                                  onTap: () => unawaited(_openExternal(instagram)),
                                ),
                              if (_normalizeTelegramUrl(profile?.telegramUsername) case final telegram?)
                                _ProfileSocialChip(
                                  icon: Icons.send_outlined,
                                  label: 'Telegram',
                                  onTap: () => unawaited(_openExternal(telegram)),
                                ),
                              if (_normalizeWebsiteUrl(profile?.websiteUrl) case final website?)
                                _ProfileSocialChip(
                                  icon: Icons.language_outlined,
                                  label: 'Website',
                                  onTap: () => unawaited(_openExternal(website)),
                                ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          (user.bio ?? profile?.bio)?.isNotEmpty == true
                              ? 18
                              : 14,
                          12,
                          16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _StatItem(
                                value: _publicationsCount,
                                label: 'публикаций',
                              ),
                            ),
                            _statDivider(),
                            Expanded(
                              child: _StatItem(
                                value:
                                    profile?.followersCount ??
                                    user.followersCount,
                                label: 'подписчиков',
                                onTap: () => context.push('/followers'),
                              ),
                            ),
                            _statDivider(),
                            Expanded(
                              child: _StatItem(
                                value:
                                    profile?.followingCount ??
                                    user.followingCount,
                                label: 'подписок',
                                onTap: () => context.push('/following'),
                              ),
                            ),
                            _statDivider(),
                            Expanded(
                              child: _StatItem(
                                value: profile?.totalReceivedPostLikes ?? 0,
                                displayValue: formatCompactCount(
                                  profile?.totalReceivedPostLikes ?? 0,
                                ),
                                label: 'лайки',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: _ProfileTabBar(
                          tabIndex: tabIndex,
                          onChanged: onTabChipTap,
                        ),
                      ),
                      if (showPostsProgress)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(14, 0, 14, 6),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                      ColoredBox(
                        color: const Color(0xFFF2F3F7),
                        child: SizedBox(
                          height: (MediaQuery.sizeOf(context).height - 260)
                              .clamp(320.0, 560.0),
                          child: PageView(
                            controller: tabPageController,
                            onPageChanged: onProfileTabSwipe,
                            children: [
                              SingleChildScrollView(
                                child: _ProductsGrid(
                                    products: profile?.products ?? []),
                              ),
                              SingleChildScrollView(
                                child: _PostsGrid(
                                  posts: newsPosts,
                                  emptyTitle: 'Нет публикаций',
                                  emptyActionLabel: 'Создать публикацию',
                                  onEmptyAction: onCreateNews,
                                  onHidePost: onHidePost,
                                ),
                              ),
                              SingleChildScrollView(
                                child: _PostsGrid(
                                  posts: publicationPosts,
                                  emptyTitle: 'Нет публикаций',
                                  emptyActionLabel: 'Создать публикацию',
                                  onEmptyAction: onCreatePublication,
                                  onHidePost: onHidePost,
                                ),
                              ),
                              SingleChildScrollView(
                                child: _PostsGrid(
                                  posts: videoPosts,
                                  emptyTitle: 'Нет видео',
                                  emptyActionLabel: 'Создать видео',
                                  onEmptyAction: onCreateVideo,
                                  onHidePost: onHidePost,
                                ),
                              ),
                              SingleChildScrollView(
                                child: _PostsGrid(
                                  posts: privatePosts,
                                  emptyTitle: 'Нет приватных публикаций',
                                  emptyActionLabel: 'Создать публикацию',
                                  onEmptyAction: onCreatePublication,
                                  onHidePost: onUnhidePost,
                                  hideActionLabel: 'Вернуть в профиль',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _statDivider() => Container(
  width: 1,
  height: 38,
  margin: const EdgeInsets.symmetric(vertical: 2),
  color: const Color(0xFFE2E5EB),
);

/// Переключатель вкладок профиля в стиле Instagram.
class _ProfileTabBar extends StatelessWidget {
  const _ProfileTabBar({required this.tabIndex, required this.onChanged});

  final int tabIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFECEEF2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFD8DCE4).withValues(alpha: 0.9),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 0,
              icon: Icons.grid_on_rounded,
              label: '',
              compact: true,
              onTap: () => onChanged(0),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 1,
              icon: Icons.article_outlined,
              label: '',
              compact: true,
              onTap: () => onChanged(1),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 2,
              icon: Icons.person_pin_outlined,
              label: '',
              compact: true,
              onTap: () => onChanged(2),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 3,
              icon: Icons.smart_display_outlined,
              label: '',
              compact: true,
              onTap: () => onChanged(3),
            ),
          ),
          const SizedBox(width: 3),
          Expanded(
            child: _ProfileTabChip(
              selected: tabIndex == 4,
              icon: Icons.lock_outline_rounded,
              label: '',
              compact: true,
              onTap: () => onChanged(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTabChip extends StatelessWidget {
  const _ProfileTabChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 17.0 : 19.0;
    final fontSize = compact ? 12.5 : 14.0;
    final gap = compact ? 4.0 : 8.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
              : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(color: Colors.black.withValues(alpha: 0.06))
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: selected
                    ? ThemedContentSurface.profileTextPrimary
                    : const Color(0xFF8E92A0),
              ),
              if (label.isNotEmpty) ...[
                SizedBox(width: gap),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? ThemedContentSurface.profileTextPrimary
                          : const Color(0xFF8E92A0),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    this.displayValue,
    this.onTap,
  });

  final int value;
  final String? displayValue;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Text(
          displayValue ?? '$value',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: ThemedContentSurface.profileTextPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: ThemedContentSurface.profileTextSecondary,
          ),
        ),
      ],
    );
    final wrapped = Center(child: content);
    if (onTap == null) return wrapped;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: wrapped,
    );
  }
}

class _ProductsGrid extends StatelessWidget {
  const _ProductsGrid({required this.products});

  final List<ProductEntity> products;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final gridThumbPx = (MediaQuery.sizeOf(context).width / 3 * dpr)
        .round()
        .clamp(64, 2048);
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 56,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text('Нет товаров', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => context.go('/add-product'),
              icon: const Icon(Icons.add),
              label: const Text('Добавить товар'),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return GestureDetector(
          onTap: () => context.push('/product/${p.id}', extra: p),
          child: CachedProductImage(
            imageUrl: p.imageUrl,
            memCacheWidth: gridThumbPx,
          ),
        );
      },
    );
  }
}

class _PostsGrid extends StatelessWidget {
  const _PostsGrid({
    required this.posts,
    required this.emptyTitle,
    required this.emptyActionLabel,
    required this.onEmptyAction,
    required this.onHidePost,
    this.hideActionLabel = 'Скрыть',
  });

  final List<PostEntity> posts;
  final String emptyTitle;
  final String emptyActionLabel;
  final Future<void> Function() onEmptyAction;
  final Future<void> Function(PostEntity post) onHidePost;
  final String hideActionLabel;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final gridThumbPx = (MediaQuery.sizeOf(context).width / 3 * dpr)
        .round()
        .clamp(64, 2048);
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(emptyTitle, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => unawaited(onEmptyAction()),
              icon: const Icon(Icons.add),
              label: Text(emptyActionLabel),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.85,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final p = posts[index];
        final hasVideo = PostGridEngagementOverlay.isProbablyVideoPost(p);
        late final Widget content;
        if (p.imageUrl.isEmpty && !hasVideo) {
          content = ColoredBox(
            color: Colors.grey.shade200,
            child: const Center(child: Icon(Icons.article_outlined, size: 32)),
          );
        } else if (hasVideo && p.imageUrl.isEmpty) {
          content = ColoredBox(
            color: Colors.grey.shade300,
            child: const Center(
              child: Icon(Icons.videocam, size: 40, color: Colors.white70),
            ),
          );
        } else {
          content = Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: p.imageUrl,
                fit: BoxFit.cover,
                memCacheWidth: gridThumbPx,
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
                placeholder: (c, u) => ColoredBox(color: Colors.grey.shade200),
                errorWidget: (c, u, e) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
              if (hasVideo)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 36,
                    color: Colors.white70,
                  ),
                ),
            ],
          );
        }
        return GestureDetector(
          onTap: () => context.push('/post/${p.id}', extra: p),
          onLongPress: () {
            showModalBottomSheet<void>(
              context: context,
              builder: (sheetContext) => SafeArea(
                child: ListTile(
                  leading: Icon(
                    hideActionLabel == 'Скрыть'
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  title: Text(hideActionLabel),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(onHidePost(p));
                  },
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: content),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PostGridEngagementOverlay(
                  post: p,
                  showViewCount: hasVideo,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileSocialChip extends StatelessWidget {
  const _ProfileSocialChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: const Color(0xFF111827)),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyProfileWarmCache {
  const _MyProfileWarmCache({
    required this.createdAt,
    required this.userId,
    required this.profile,
    required this.newsPosts,
    required this.publicationPosts,
    required this.videoPosts,
    required this.storyGroups,
    required this.newStoriesByUserId,
    required this.myStoryNote,
  });

  final DateTime createdAt;
  final String userId;
  final SellerProfileEntity? profile;
  final List<PostEntity> newsPosts;
  final List<PostEntity> publicationPosts;
  final List<PostEntity> videoPosts;
  final List<StoryGroupEntity> storyGroups;
  final Map<String, bool> newStoriesByUserId;
  final String myStoryNote;
}
