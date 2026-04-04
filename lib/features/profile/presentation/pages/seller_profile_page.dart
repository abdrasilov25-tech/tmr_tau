import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/formatting/compact_count_format.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/app_error_view.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/verified_badge.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../post/presentation/widgets/post_grid_engagement_overlay.dart';
import '../../../chat/presentation/widgets/start_chat_button.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../product/presentation/bloc/payment_cubit.dart';
import '../../domain/entities/seller_profile_entity.dart';
import '../../domain/repositories/profile_repository.dart';
import '../bloc/profile_bloc.dart';
import '../../../settings/data/repositories/settings_repository_impl.dart';

class SellerProfilePage extends StatefulWidget {
  const SellerProfilePage({super.key, required this.sellerId});

  final String sellerId;

  @override
  State<SellerProfilePage> createState() => _SellerProfilePageState();
}

class _SellerProfilePageState extends State<SellerProfilePage> {
  bool _actionsSheetOpen = false;

  String _profileUrl(String userId) => 'https://tmr-tau.app/profile/$userId';

  Future<bool> _isBlockedByMe(String currentUserId) async {
    final row = await Supabase.instance.client
        .from('blocked_users')
        .select('blocked_user_id')
        .eq('blocker_id', currentUserId)
        .eq('blocked_user_id', widget.sellerId)
        .maybeSingle();
    return row != null;
  }

  Future<bool> _isMutualFollow(String currentUserId) async {
    final meFollowsPeer = await Supabase.instance.client
        .from(SupabaseConstants.followersTable)
        .select('follower_id')
        .eq('follower_id', currentUserId)
        .eq('following_id', widget.sellerId)
        .maybeSingle();
    if (meFollowsPeer == null) return false;
    final peerFollowsMe = await Supabase.instance.client
        .from(SupabaseConstants.followersTable)
        .select('follower_id')
        .eq('follower_id', widget.sellerId)
        .eq('following_id', currentUserId)
        .maybeSingle();
    return peerFollowsMe != null;
  }

  Future<bool> _isMyStoryHiddenForPeer() async {
    final current = Supabase.instance.client.auth.currentUser?.id;
    if (current == null) return false;
    final row = await Supabase.instance.client
        .from(SupabaseConstants.hiddenStoriesTable)
        .select('hidden_user_id')
        .eq('owner_id', current)
        .eq('hidden_user_id', widget.sellerId)
        .maybeSingle();
    return row != null;
  }

  Future<void> _toggleMyStoryHiddenForPeer(bool hide) async {
    final current = Supabase.instance.client.auth.currentUser?.id;
    if (current == null) return;
    if (hide) {
      await Supabase.instance.client
          .from(SupabaseConstants.hiddenStoriesTable)
          .upsert({'owner_id': current, 'hidden_user_id': widget.sellerId});
    } else {
      await Supabase.instance.client
          .from(SupabaseConstants.hiddenStoriesTable)
          .delete()
          .eq('owner_id', current)
          .eq('hidden_user_id', widget.sellerId);
    }
  }

  Future<void> _toggleBlockUser(
    String currentUserId,
    bool currentlyBlocked,
  ) async {
    final repo = SettingsRepositoryImpl(Supabase.instance.client);
    if (currentlyBlocked) {
      await repo.unblockUser(
        blockerId: currentUserId,
        blockedUserId: widget.sellerId,
      );
      return;
    }
    await repo.blockUser(
      blockerId: currentUserId,
      blockedUserId: widget.sellerId,
    );
  }

  Future<void> _removeFollower(String currentUserId) async {
    await Supabase.instance.client
        .from(SupabaseConstants.followersTable)
        .delete()
        .eq('follower_id', widget.sellerId)
        .eq('following_id', currentUserId);
  }

  Future<void> _showProfileActionsSheet(
    BuildContext context, {
    required String currentUserId,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final blocked = await _isBlockedByMe(currentUserId);
    final mutual = await _isMutualFollow(currentUserId);
    final storyHidden = await _isMyStoryHiddenForPeer();
    if (!context.mounted) return;

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  blocked ? Icons.block : Icons.block_outlined,
                  color: Colors.redAccent,
                ),
                title: Text(blocked ? 'Разблокировать' : 'Заблокировать'),
                onTap: () => Navigator.pop(sheetContext, 'block'),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: Text(
                  storyHidden ? 'Показывать мою историю' : 'Скрыть мою историю',
                ),
                onTap: () => Navigator.pop(sheetContext, 'story'),
              ),
              if (mutual)
                ListTile(
                  leading: const Icon(Icons.person_remove_alt_1_outlined),
                  title: const Text('Удалить подписчика'),
                  onTap: () => Navigator.pop(sheetContext, 'remove_follower'),
                ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('Скопировать URL пользователя'),
                onTap: () => Navigator.pop(sheetContext, 'copy_url'),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: const Text('Поделиться этим пользователем'),
                onTap: () => Navigator.pop(sheetContext, 'share'),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Отмена'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selected == null || !context.mounted) return;

    try {
      switch (selected) {
        case 'block':
        await _toggleBlockUser(currentUserId, blocked);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                blocked
                    ? 'Пользователь разблокирован'
                    : 'Пользователь заблокирован',
              ),
            ),
          );
          break;
        case 'story':
          await _toggleMyStoryHiddenForPeer(!storyHidden);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                storyHidden
                    ? 'Пользователь снова видит вашу историю'
                    : 'Ваша история скрыта от этого пользователя',
              ),
            ),
          );
          break;
        case 'remove_follower':
          await _removeFollower(currentUserId);
          messenger.showSnackBar(
            const SnackBar(content: Text('Подписчик удален')),
          );
          break;
        case 'copy_url':
          final url = _profileUrl(widget.sellerId);
          await Clipboard.setData(ClipboardData(text: url));
          messenger.showSnackBar(
            const SnackBar(content: Text('Ссылка скопирована')),
          );
          break;
        case 'share':
          final url = _profileUrl(widget.sellerId);
          await SharePlus.instance.share(ShareParams(text: url));
          break;
      }
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось выполнить действие: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<AuthBloc>().state is AuthAuthenticated
        ? (context.read<AuthBloc>().state as AuthAuthenticated).user.id
        : null;
    return BlocProvider(
      create: (c) =>
          ProfileBloc(c.read<ProfileRepository>())
            ..add(
              ProfileLoadRequested(widget.sellerId, currentUserId: currentUserId),
            ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Профиль'),
          actions: [
            if (currentUserId != null && currentUserId != widget.sellerId)
              IconButton(
                icon: const Icon(Icons.more_horiz),
                onPressed: _actionsSheetOpen
                    ? null
                    : () async {
                        setState(() => _actionsSheetOpen = true);
                        try {
                          await _showProfileActionsSheet(
                            context,
                            currentUserId: currentUserId,
                          );
                        } finally {
                          if (mounted) {
                            setState(() => _actionsSheetOpen = false);
                          }
                        }
                      },
              ),
          ],
        ),
        body: BlocBuilder<ProfileBloc, ProfileState>(
          builder: (context, state) {
            if (state is ProfileLoading) return const AppLoading();
            if (state is ProfileFailure) {
              return AppErrorView(
                message: state.message,
                onRetry: () => context.read<ProfileBloc>().add(
                  ProfileLoadRequested(widget.sellerId),
                ),
              );
            }
            if (state is ProfileSuccess) {
              return _SellerProfileView(profile: state.profile);
            }
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}

class _SellerProfileView extends StatefulWidget {
  const _SellerProfileView({required this.profile});

  final SellerProfileEntity profile;

  @override
  State<_SellerProfileView> createState() => _SellerProfileViewState();
}

class _SellerProfileViewState extends State<_SellerProfileView> {
  int _tabIndex = 0;
  List<PostEntity> _publicationPosts = const [];
  bool _loadingPublications = true;
  String? _currentUserId;
  bool _isMutualFollow = false;

  /// Подписчик подписан на вас, а вы на него ещё нет (как подпись в Instagram).
  bool _peerFollowsMe = false;
  List<SellerProfileEntity> _commonFollowers = const [];

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
  void initState() {
    super.initState();
    final authState = context.read<AuthBloc>().state;
    if (authState is AuthAuthenticated) {
      _currentUserId = authState.user.id;
    }
    _loadPublications();
    _loadFollowState();
    _loadCommonFollowers();
  }

  @override
  void didUpdateWidget(covariant _SellerProfileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.isFollowingByMe != widget.profile.isFollowingByMe) {
      _loadFollowState();
      _loadCommonFollowers();
    }
  }

  Future<void> _loadPublications() async {
    try {
      final posts = await context.read<PostRepository>().getPostsByUser(
        widget.profile.id,
        currentUserId: _currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _publicationPosts = posts
            .where((p) => p.kind.trim().toLowerCase() == 'publication')
            .toList(growable: false);
        _loadingPublications = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPublications = false);
    }
  }

  /// Один параллельный запрос вместо двух последовательных.
  Future<void> _loadFollowState() async {
    final me = _currentUserId;
    if (me == null || me == widget.profile.id) {
      if (!mounted) return;
      setState(() { _peerFollowsMe = false; _isMutualFollow = false; });
      return;
    }
    try {
      final results = await Future.wait([
        Supabase.instance.client
            .from(SupabaseConstants.followersTable)
            .select('follower_id')
            .eq('follower_id', widget.profile.id)
            .eq('following_id', me)
            .maybeSingle(),
        if (widget.profile.isFollowingByMe)
          Supabase.instance.client
              .from(SupabaseConstants.followersTable)
              .select('follower_id')
              .eq('follower_id', widget.profile.id)
              .eq('following_id', me)
              .maybeSingle()
        else
          Future<dynamic>.value(null),
      ]);
      final peerFollowsMe = results[0] != null;
      if (!mounted) return;
      setState(() {
        _peerFollowsMe = peerFollowsMe;
        _isMutualFollow = widget.profile.isFollowingByMe && peerFollowsMe;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _peerFollowsMe = false; _isMutualFollow = false; });
    }
  }

  Future<void> _loadCommonFollowers() async {
    final me = _currentUserId;
    if (me == null || me == widget.profile.id) {
      if (!mounted) return;
      setState(() => _commonFollowers = const []);
      return;
    }
    try {
      final myFollowingRes = await Supabase.instance.client
          .from(SupabaseConstants.followersTable)
          .select('following_id')
          .eq('follower_id', me);
      final myFollowingIds = (myFollowingRes as List)
          .map((e) => (e as Map<String, dynamic>)['following_id'] as String?)
          .whereType<String>()
          .toSet();
      if (myFollowingIds.isEmpty) {
        if (!mounted) return;
        setState(() => _commonFollowers = const []);
        return;
      }

      final targetFollowersRes = await Supabase.instance.client
          .from(SupabaseConstants.followersTable)
          .select('follower_id')
          .eq('following_id', widget.profile.id);
      final targetFollowerIds = (targetFollowersRes as List)
          .map((e) => (e as Map<String, dynamic>)['follower_id'] as String?)
          .whereType<String>()
          .toSet();
      if (targetFollowerIds.isEmpty) {
        if (!mounted) return;
        setState(() => _commonFollowers = const []);
        return;
      }

      final commonIds = myFollowingIds.intersection(targetFollowerIds).toList();
      if (commonIds.isEmpty) {
        if (!mounted) return;
        setState(() => _commonFollowers = const []);
        return;
      }

      final usersRes = await Supabase.instance.client
          .from(SupabaseConstants.usersTable)
          .select('id,name,avatar,bio')
          .inFilter('id', commonIds.take(20).toList(growable: false));
      final rows = (usersRes as List).cast<Map<String, dynamic>>();
      final mapped = rows
          .map(
            (m) => SellerProfileEntity(
              id: m['id'] as String,
              name: (m['name'] as String?) ?? 'Пользователь',
              avatarUrl: m['avatar'] as String?,
              bio: m['bio'] as String?,
              followersCount: 0,
              followingCount: 0,
              totalReceivedPostLikes: 0,
              isFollowingByMe: true,
              products: const [],
              isVerified: false,
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _commonFollowers = mapped);
    } catch (_) {
      if (!mounted) return;
      setState(() => _commonFollowers = const []);
    }
  }

  Future<void> _showCommonFollowersSheet() async {
    if (_commonFollowers.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Общие',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _commonFollowers.length,
                itemBuilder: (context, index) {
                  final u = _commonFollowers[index];
                  return ListTile(
                    leading: CachedAvatar(
                      imageUrl: u.avatarUrl,
                      radius: 22,
                      fallbackText: u.name,
                    ),
                    title: Text(u.name),
                    subtitle: u.bio != null && u.bio!.isNotEmpty
                        ? Text(
                            u.bio!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      context.push('/profile/${u.id}');
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

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: DecoratedBox(
              decoration: ThemedContentSurface.profileCardDecoration(),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        final imageUrl = profile.avatarUrl;
                        if (imageUrl == null || imageUrl.isEmpty) return;
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => Dialog(
                            backgroundColor: Colors.black,
                            insetPadding: const EdgeInsets.all(24),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: InteractiveViewer(
                                child: CachedNetworkImage(
                                  imageUrl: imageUrl,
                                  fit: BoxFit.cover,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                  placeholder: (context, url) =>
                                      const ColoredBox(color: Colors.black26),
                                  errorWidget: (context, url, error) =>
                                      const ColoredBox(color: Colors.black54),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      child: CachedAvatar(
                        imageUrl:
                            profile.avatarUrl != null &&
                                profile.avatarUrl!.isNotEmpty
                            ? '${profile.avatarUrl}?uid=${profile.id}'
                            : null,
                        radius: 48,
                        fallbackText: profile.name,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          profile.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: ThemedContentSurface.profileTextPrimary,
                              ),
                        ),
                        if (profile.isVerified) ...[
                          const SizedBox(width: 6),
                          const VerifiedBadge(size: 22),
                        ],
                      ],
                    ),
                    if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          profile.bio!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color:
                                    ThemedContentSurface.profileTextSecondary,
                                height: 1.35,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    if (_normalizeInstagramUrl(profile.instagramUrl) != null ||
                        _normalizeTelegramUrl(profile.telegramUsername) != null ||
                        _normalizeWebsiteUrl(profile.websiteUrl) != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_normalizeInstagramUrl(profile.instagramUrl) case final instagram?)
                            _SellerProfileSocialChip(
                              icon: Icons.camera_alt_outlined,
                              label: 'Instagram',
                              onTap: () => _openExternal(instagram),
                            ),
                          if (_normalizeTelegramUrl(profile.telegramUsername) case final telegram?)
                            _SellerProfileSocialChip(
                              icon: Icons.send_outlined,
                              label: 'Telegram',
                              onTap: () => _openExternal(telegram),
                            ),
                          if (_normalizeWebsiteUrl(profile.websiteUrl) case final website?)
                            _SellerProfileSocialChip(
                              icon: Icons.language_outlined,
                              label: 'Website',
                              onTap: () => _openExternal(website),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _SellerTikTokStat(
                            value: '${profile.followersCount}',
                            label: 'подписчиков',
                          ),
                        ),
                        Expanded(
                          child: _SellerTikTokStat(
                            value: '${profile.followingCount}',
                            label: 'подписок',
                          ),
                        ),
                        Expanded(
                          child: _SellerTikTokStat(
                            value: formatCompactCount(
                              profile.totalReceivedPostLikes,
                            ),
                            label: 'лайки',
                          ),
                        ),
                      ],
                    ),
                    if (profile.products.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '${profile.products.length} товаров',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ThemedContentSurface.profileTextSecondary,
                        ),
                      ),
                    ],
                    if (_commonFollowers.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _showCommonFollowersSheet,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 74,
                                height: 28,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    for (
                                      var i = 0;
                                      i <
                                          (_commonFollowers.length < 3
                                              ? _commonFollowers.length
                                              : 3);
                                      i++
                                    )
                                      Positioned(
                                        left: i * 18,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          child: CachedAvatar(
                                            imageUrl:
                                                _commonFollowers[i].avatarUrl,
                                            radius: 13,
                                            fallbackText:
                                                _commonFollowers[i].name,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _commonFollowers.length == 1
                                      ? 'Подписаны: ${_commonFollowers.first.name}'
                                      : 'Подписаны: ${_commonFollowers.take(2).map((u) => u.name).join(', ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: ThemedContentSurface
                                            .profileTextSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (_currentUserId != null &&
                        _currentUserId != profile.id) ...[
                      if (!profile.isFollowingByMe && _peerFollowsMe) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Подписан на вас',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color:
                                    ThemedContentSurface.profileTextSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: profile.isFollowingByMe
                                ? FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF22C55E),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () async {
                                      final uid =
                                          (context.read<AuthBloc>().state
                                                  as AuthAuthenticated)
                                              .user
                                              .id;
                                      context.read<ProfileBloc>().add(
                                        ProfileToggleFollow(
                                          followerId: uid,
                                          followingId: profile.id,
                                        ),
                                      );
                                      await Future<void>.delayed(
                                        const Duration(milliseconds: 220),
                                      );
                                      if (!mounted) return;
                                      await _loadFollowState();
                                    },
                                    icon: const Icon(Icons.check_rounded, size: 18),
                                    label: Text(
                                      _isMutualFollow
                                          ? 'Вы подписаны'
                                          : 'Отписаться',
                                    ),
                                  )
                                : FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFFEF4444),
                                      foregroundColor: Colors.white,
                                    ),
                                    onPressed: () async {
                                      final uid =
                                          (context.read<AuthBloc>().state
                                                  as AuthAuthenticated)
                                              .user
                                              .id;
                                      context.read<ProfileBloc>().add(
                                        ProfileToggleFollow(
                                          followerId: uid,
                                          followingId: profile.id,
                                        ),
                                      );
                                      await Future<void>.delayed(
                                        const Duration(milliseconds: 220),
                                      );
                                      if (!mounted) return;
                                      await _loadFollowState();
                                    },
                                    icon: const Icon(Icons.person_add_rounded, size: 18),
                                    label: Text(
                                      _peerFollowsMe
                                          ? 'Подписаться в ответ'
                                          : 'Подписаться',
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StartChatButton(
                              peerId: profile.id,
                              peerName: profile.name,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_currentUserId != null &&
                        _currentUserId == profile.id) ...[
                      const SizedBox(height: 16),
                      const _OwnQarmetProfilePanel(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: DecoratedBox(
              decoration: ThemedContentSurface.profileCardDecoration(
                radius: 16,
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: _ProfileTabChip(
                        selected: _tabIndex == 0,
                        icon: Icons.shopping_bag_outlined,
                        label: 'Товары',
                        onTap: () => setState(() => _tabIndex = 0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ProfileTabChip(
                        selected: _tabIndex == 1,
                        icon: Icons.person_outline_rounded,
                        label: 'Лента',
                        onTap: () => setState(() => _tabIndex = 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_tabIndex == 0)
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            delegate: SliverChildBuilderDelegate((context, index) {
              final product = profile.products[index];
              return _ProductGridTile(
                product: product,
                onTap: () =>
                    context.push('/product/${product.id}', extra: product),
              );
            }, childCount: profile.products.length),
          )
        else
          SliverToBoxAdapter(
            child: _ProfilePublicationsGrid(
              posts: _publicationPosts,
              loading: _loadingPublications,
            ),
          ),
      ],
    );
  }
}

class _ProductGridTile extends StatelessWidget {
  const _ProductGridTile({required this.product, required this.onTap});

  final ProductEntity product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: CachedProductImage(
                imageUrl: product.imageUrl,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                product.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                product.priceFormatted,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
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
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.black87 : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black87 : Colors.grey,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfilePublicationsGrid extends StatelessWidget {
  const _ProfilePublicationsGrid({required this.posts, required this.loading});

  final List<PostEntity> posts;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Нет публикаций',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final gridThumbPx = (MediaQuery.sizeOf(context).width / 3 * dpr)
        .round()
        .clamp(64, 2048);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            child: const Center(child: Icon(Icons.person_outline_rounded)),
          );
        } else if (hasVideo && p.imageUrl.isEmpty) {
          content = ColoredBox(
            color: Colors.grey.shade300,
            child: const Center(
              child: Icon(
                Icons.play_circle_fill,
                size: 36,
                color: Colors.white70,
              ),
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
                placeholder: (context, url) =>
                    ColoredBox(color: Colors.grey.shade200),
                errorWidget: (context, url, error) => Container(
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
              if (hasVideo)
                const Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 34,
                    color: Colors.white70,
                  ),
                ),
            ],
          );
        }
        return GestureDetector(
          onTap: () => context.push('/post/${p.id}', extra: p),
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

class _SellerTikTokStat extends StatelessWidget {
  const _SellerTikTokStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: ThemedContentSurface.profileTextPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: ThemedContentSurface.profileTextSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _SellerProfileSocialChip extends StatelessWidget {
  const _SellerProfileSocialChip({
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

class _OwnQarmetProfilePanel extends StatefulWidget {
  const _OwnQarmetProfilePanel();

  @override
  State<_OwnQarmetProfilePanel> createState() => _OwnQarmetProfilePanelState();
}

class _OwnQarmetProfilePanelState extends State<_OwnQarmetProfilePanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PaymentCubit>().initStore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PaymentCubit, PaymentUiState>(
        listenWhen: (prev, next) =>
            prev.status != next.status && next.status != PaymentUiStatus.loading,
        listener: (context, state) {
          final messenger = ScaffoldMessenger.of(context);
          switch (state.status) {
            case PaymentUiStatus.success:
              messenger.showSnackBar(
                const SnackBar(content: Text('Готово')),
              );
            case PaymentUiStatus.error:
              messenger.showSnackBar(
                SnackBar(
                  content: Text(state.message ?? 'Ошибка'),
                ),
              );
            case PaymentUiStatus.cancelled:
              messenger.showSnackBar(
                SnackBar(
                  content: Text(state.message ?? 'Отменено'),
                ),
              );
            default:
              return;
          }
          context.read<PaymentCubit>().clearStatus();
        },
        builder: (context, state) {
          final loading = state.status == PaymentUiStatus.loading;
          final cosmetics = state.cosmeticsLifetimeUnlocked;
          return DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Qarmet в профиле: ${state.balance}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (cosmetics) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Оформление навсегда: галочка, рамка и значок без списания Qarmet.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (!cosmetics)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: loading
                            ? null
                            : () => context
                                .read<PaymentCubit>()
                                .purchaseProfileCosmeticsLifetime(),
                        child: const Text('Оформление навсегда (IAP)'),
                      ),
                    ),
                  if (!cosmetics) const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: loading
                            ? null
                            : () => context
                                  .read<PaymentCubit>()
                                  .spendPremiumBadge(cost: 5),
                        child: Text(cosmetics ? 'Галочка' : 'Галочка (5)'),
                      ),
                      FilledButton.tonal(
                        onPressed: loading
                            ? null
                            : () => context.read<PaymentCubit>().spendFrame(
                                  level: 2,
                                  cost: 2,
                                ),
                        child: Text(cosmetics ? 'Рамка' : 'Рамка (2)'),
                      ),
                      FilledButton.tonal(
                        onPressed: loading
                            ? null
                            : () => context.read<PaymentCubit>().spendBadge(
                                  level: 3,
                                  cost: 3,
                                ),
                        child: Text(cosmetics ? 'Значок' : 'Значок (3)'),
                      ),
                      OutlinedButton(
                        onPressed: loading
                            ? null
                            : () =>
                                  context
                                      .read<PaymentCubit>()
                                      .refreshWallet(forceRefresh: true),
                        child: const Text('Обновить'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
    );
  }
}
