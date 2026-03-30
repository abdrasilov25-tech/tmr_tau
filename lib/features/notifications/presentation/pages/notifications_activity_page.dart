import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/formatting/compact_count_format.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../comments/domain/repositories/comments_repository.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/entities/top_user_rank_entity.dart';
import '../../domain/repositories/notifications_repository.dart';
import '../notification_activity_peek_bus.dart';
import '../notification_tab_badge_controller.dart';

class _ActivityRow {
  _ActivityRow(this.members) : assert(members.isNotEmpty);

  final List<NotificationEntity> members;
  NotificationEntity get primary => members.first;
  bool get anyUnread => members.any((n) => !n.isRead);
  List<String> get allIds => members.map((n) => n.id).toList();
}

class NotificationsActivityPage extends StatefulWidget {
  const NotificationsActivityPage({super.key});

  @override
  State<NotificationsActivityPage> createState() =>
      _NotificationsActivityPageState();
}

class _NotificationsActivityPageState extends State<NotificationsActivityPage> {
  bool _loading = true;
  bool _markingAll = false;
  String? _error;
  List<NotificationEntity> _items = const [];
  List<TopUserRankEntity> _topUsers = const [];
  supa.RealtimeChannel? _topUsersChannel;
  Timer? _topUsersRefreshDebounce;

  static const _groupableTypes = {
    'post_like',
    'post_repost',
    'product_like',
    'product_repost',
    'product_favorite',
  };

  @override
  void initState() {
    super.initState();
    _attachTopUsersRealtime();
    _load();
  }

  @override
  void dispose() {
    _topUsersRefreshDebounce?.cancel();
    _detachTopUsersRealtime();
    super.dispose();
  }

  void _attachTopUsersRealtime() {
    _detachTopUsersRealtime();
    final ch = supa.Supabase.instance.client.channel('top_users_realtime');
    _topUsersChannel = ch;
    ch
        .onPostgresChanges(
          event: supa.PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          callback: (_) => _scheduleTopUsersRefresh(),
        )
        .subscribe();
  }

  void _detachTopUsersRealtime() {
    final ch = _topUsersChannel;
    _topUsersChannel = null;
    if (ch != null) {
      supa.Supabase.instance.client.removeChannel(ch);
    }
  }

  void _scheduleTopUsersRefresh() {
    _topUsersRefreshDebounce?.cancel();
    _topUsersRefreshDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _loadTopUsersOnly();
    });
  }

  Future<void> _loadTopUsersOnly() async {
    try {
      final top = await context.read<NotificationsRepository>().getTopUsersByLikes(limit: 12);
      if (!mounted) return;
      setState(() => _topUsers = top);
    } catch (_) {
      // Не ломаем экран уведомлений, если realtime-подгрузка не удалась.
    }
  }

  Future<void> _load() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) {
      setState(() {
        _loading = false;
        _error = 'Войдите, чтобы смотреть уведомления';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<NotificationsRepository>();
      final list = await repo.getNotifications(userId);
      final top = await repo.getTopUsersByLikes(limit: 12);
      if (!mounted) return;
      setState(() {
        _items = list;
        _topUsers = top;
        _loading = false;
      });
      final hadUnread = list.any((n) => !n.isRead);
      if (hadUnread) {
        await repo.markAllAsRead(userId);
        if (!mounted) return;
        final fresh = await repo.getNotifications(userId);
        if (!mounted) return;
        setState(() => _items = fresh);
        _notifyUnreadBadges();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _markAllRead() async {
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) return;
    setState(() => _markingAll = true);
    try {
      await context.read<NotificationsRepository>().markAllAsRead(userId);
      if (!mounted) return;
      await _load();
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
    if (mounted) _notifyUnreadBadges();
  }

  void _notifyUnreadBadges() {
    if (!context.mounted) return;
    try {
      context.read<NotificationActivityPeekBus>().notifyUnreadMayHaveChanged();
    } catch (_) {}
    try {
      unawaited(context.read<NotificationTabBadgeController>().refresh());
    } catch (_) {}
  }

  Future<void> _markGroupRead(List<String> ids) async {
    if (ids.isEmpty) return;
    final authState = context.read<AuthBloc>().state;
    final userId = authState is AuthAuthenticated ? authState.user.id : null;
    if (userId == null) return;
    await context.read<NotificationsRepository>().markAsReadMany(ids, userId);
    if (!mounted) return;
    final now = DateTime.now();
    final idSet = ids.toSet();
    setState(() {
      _items = _items
          .map(
            (n) => idSet.contains(n.id)
                ? NotificationEntity(
                    id: n.id,
                    userId: n.userId,
                    type: n.type,
                    createdAt: n.createdAt,
                    actorId: n.actorId,
                    actorName: n.actorName,
                    actorAvatarUrl: n.actorAvatarUrl,
                    title: n.title,
                    body: n.body,
                    productId: n.productId,
                    postId: n.postId,
                    subjectImageUrl: n.subjectImageUrl,
                    subjectVideoUrl: n.subjectVideoUrl,
                    relatedPostKind: n.relatedPostKind,
                    commentId: n.commentId,
                    readAt: now,
                  )
                : n,
          )
          .toList(growable: false);
    });
    _notifyUnreadBadges();
  }

  List<_ActivityRow> _buildRows() {
    final sorted = List<NotificationEntity>.from(_items)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final consumed = <String>{};
    final rows = <_ActivityRow>[];
    for (final n in sorted) {
      if (consumed.contains(n.id)) continue;
      if (!_groupableTypes.contains(n.type)) {
        rows.add(_ActivityRow([n]));
        consumed.add(n.id);
        continue;
      }
      final sk = _subjectKey(n);
      if (sk == null) {
        rows.add(_ActivityRow([n]));
        consumed.add(n.id);
        continue;
      }
      final members = <NotificationEntity>[];
      for (final o in sorted) {
        if (consumed.contains(o.id)) continue;
        if (o.type != n.type) continue;
        if (_subjectKey(o) != sk) continue;
        members.add(o);
        consumed.add(o.id);
      }
      members.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      rows.add(_ActivityRow(members));
    }
    return rows;
  }

  static String? _subjectKey(NotificationEntity n) {
    final pid = n.postId ?? _extractPostId(n.body);
    if (pid != null && pid.isNotEmpty) return 'post:$pid';
    final pr = n.productId;
    if (pr != null && pr.isNotEmpty) return 'product:$pr';
    return null;
  }

  Future<void> _onOpenRow(BuildContext context, _ActivityRow row) async {
    await _markGroupRead(row.allIds);
    if (!context.mounted) return;
    final item = row.primary;
    final postId = item.postId ?? _extractPostId(item.body);
    if (postId != null && postId.isNotEmpty) {
      await context.push('/post/$postId');
      return;
    }
    final productId = item.productId;
    if (productId != null && productId.isNotEmpty) {
      final auth = context.read<AuthBloc>().state;
      final uid = auth is AuthAuthenticated ? auth.user.id : null;
      final product = await context
          .read<ProductRepository>()
          .getProductById(productId, currentUserId: uid);
      if (!context.mounted) return;
      if (product != null) {
        await context.push('/product/$productId', extra: product);
      }
    }
  }

  Future<void> _onReplyComment(BuildContext context, _ActivityRow row) async {
    await _markGroupRead(row.allIds);
    if (!context.mounted) return;
    final item = row.primary;
    if (item.type == 'post_comment') {
      final postId = item.postId ?? _extractPostId(item.body);
      if (postId == null || postId.isEmpty) return;
      final cid = item.commentId?.trim();
      final path = (cid != null && cid.isNotEmpty)
          ? '/post/$postId?replyTo=$cid'
          : '/post/$postId';
      await context.push(path);
    } else if (item.type == 'product_comment') {
      final productId = item.productId;
      if (productId == null || productId.isEmpty) return;
      final auth = context.read<AuthBloc>().state;
      final uid = auth is AuthAuthenticated ? auth.user.id : null;
      final product = await context
          .read<ProductRepository>()
          .getProductById(productId, currentUserId: uid);
      if (!context.mounted) return;
      if (product == null) return;
      final name = item.actorName?.trim() ?? '';
      final path = name.isEmpty
          ? '/product/$productId'
          : '/product/$productId?mention=${Uri.encodeQueryComponent(name)}';
      await context.push(path, extra: product);
    }
  }

  Future<void> _toggleCommentLike(_ActivityRow row) async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Войдите, чтобы ставить лайки')),
        );
      }
      throw StateError('unauthenticated');
    }
    final item = row.primary;
    final cid = item.commentId;
    if (cid == null || cid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Для старых уведомлений обновите схему БД (comment_id).'),
          ),
        );
      }
      throw StateError('no comment_id');
    }
    try {
      if (item.type == 'post_comment') {
        await context.read<PostRepository>().togglePostCommentLike(cid, auth.user.id);
      } else if (item.type == 'product_comment') {
        await context
            .read<CommentsRepository>()
            .toggleProductCommentLike(cid, auth.user.id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось: $e')),
        );
      }
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: ThemedContentSurface.scaffold,
      appBar: AppBar(
        title: const Text('Уведомления'),
        centerTitle: true,
        backgroundColor: ThemedContentSurface.scaffoldElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black12,
        actions: [
          TextButton(
            onPressed: _markingAll ? null : _markAllRead,
            child: _markingAll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Прочитать всё',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: ThemedContentSurface.profileTextSecondary,
                      ),
                    ),
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        'Пока нет уведомлений',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: ThemedContentSurface.profileTextSecondary,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (_topUsers.isNotEmpty) ...[
                            _TopUsersByLikesCard(users: _topUsers),
                            const SizedBox(height: 4),
                          ],
                          ..._buildGroupedList(context),
                        ],
                      ),
                    ),
    );
  }

  List<Widget> _buildGroupedList(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final children = <Widget>[];
    String? lastDay;
    final rows = _buildRows();

    for (final row in rows) {
      final item = row.primary;
      final day = _dayLabel(item.createdAt, now);
      if (day != lastDay) {
        lastDay = day;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              day,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: ThemedContentSurface.profileTextSecondary,
              ),
            ),
          ),
        );
      }
      final isComment =
          item.type == 'post_comment' || item.type == 'product_comment';
      final hasCommentRef =
          item.commentId != null && item.commentId!.trim().isNotEmpty;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: _NotificationTile(
            row: row,
            relativeTime: _relativeTimeRu(item.createdAt, now),
            mergedNames: _mergedNamesRu(row.members),
            actionText: _actionSuffix(row.primary),
            displayBody: _displayBody(item.body),
            accent: _accentForType(item.type),
            icon: _iconByType(item.type),
            onOpen: () => _onOpenRow(context, row),
            showCommentActions: isComment,
            onReply: isComment ? () => _onReplyComment(context, row) : null,
            onLikeComment: isComment && hasCommentRef
                ? () => _toggleCommentLike(row)
                : null,
            commentId: item.commentId,
          ),
        ),
      );
    }
    return children;
  }

  static String _mergedNamesRu(List<NotificationEntity> members) {
    final seen = <String>{};
    final names = <String>[];
    for (final m in members) {
      final n = m.actorName?.trim();
      if (n == null || n.isEmpty) continue;
      if (seen.add(n)) names.add(n);
    }
    if (names.isEmpty) return 'Пользователи';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]}, ${names[1]}';
    final rest = names.length - 2;
    return '${names[0]}, ${names[1]} и ещё $rest';
  }

  static String _actionSuffix(NotificationEntity n) {
    switch (n.type) {
      case 'post_like':
        return 'лайкнули ${_postKindAccusative(n.relatedPostKind)}';
      case 'post_repost':
        return 'поделились ${_postKindInstrumental(n.relatedPostKind)}';
      case 'product_like':
        return 'лайкнули объявление';
      case 'product_repost':
        return 'поделились объявлением';
      case 'product_favorite':
        return 'добавили объявление в избранное';
      case 'post_comment':
        return 'прокомментировали ${_postKindAccusative(n.relatedPostKind)}';
      case 'product_comment':
        return 'прокомментировали объявление';
      default:
        return n.title ?? '';
    }
  }

  static String _postKindAccusative(String? k) {
    switch (k?.toLowerCase()) {
      case 'news':
        return 'новость';
      case 'publication':
        return 'публикацию';
      default:
        return 'публикацию';
    }
  }

  static String _postKindInstrumental(String? k) {
    switch (k?.toLowerCase()) {
      case 'news':
        return 'новостью';
      case 'publication':
        return 'публикацией';
      default:
        return 'публикацией';
    }
  }

  static String _dayLabel(DateTime createdAt, DateTime now) {
    final local = createdAt.toLocal();
    final a = DateTime(local.year, local.month, local.day);
    final t = DateTime(now.year, now.month, now.day);
    if (a == t) return 'Сегодня';
    if (a == t.subtract(const Duration(days: 1))) return 'Вчера';
    return '${local.day}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  static String _relativeTimeRu(DateTime createdAt, DateTime now) {
    final d = createdAt.toLocal();
    var delta = now.difference(d);
    if (delta.isNegative) delta = Duration.zero;
    if (delta.inSeconds < 45) return 'только что';
    if (delta.inMinutes < 60) return '${delta.inMinutes} мин';
    if (delta.inHours < 24) return '${delta.inHours} ч';
    if (delta.inDays < 7) return '${delta.inDays} дн';
    return '${d.day}.${d.month.toString().padLeft(2, '0')}';
  }

  static String _displayBody(String? body) {
    if (body == null || body.isEmpty) return '';
    return body
        .replaceAll(RegExp(r'\s*\[post:[a-fA-F0-9\-]{36}\]\s*'), ' ')
        .trim();
  }

  static IconData _iconByType(String type) {
    switch (type) {
      case 'post_like':
      case 'product_like':
        return Icons.favorite_rounded;
      case 'post_comment':
      case 'product_comment':
        return Icons.chat_bubble_rounded;
      case 'post_repost':
      case 'product_repost':
        return Icons.repeat_rounded;
      case 'product_favorite':
        return Icons.bookmark_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  static Color _accentForType(String type) {
    switch (type) {
      case 'post_like':
      case 'product_like':
        return const Color(0xFFE91E63);
      case 'post_comment':
      case 'product_comment':
        return const Color(0xFF1565C0);
      case 'post_repost':
      case 'product_repost':
        return const Color(0xFF6A1B9A);
      case 'product_favorite':
        return const Color(0xFFFB8C00);
      default:
        return const Color(0xFF455A64);
    }
  }

  static String? _extractPostId(String? body) {
    if (body == null || body.isEmpty) return null;
    final match = RegExp(r'\[post:([a-fA-F0-9\-]{36})\]').firstMatch(body);
    return match?.group(1);
  }
}

class _TopUsersByLikesCard extends StatelessWidget {
  const _TopUsersByLikesCard({required this.users});

  final List<TopUserRankEntity> users;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF232A3B),
              Color(0xFF1B1E2B),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 24,
              offset: const Offset(0, 10),
              spreadRadius: -8,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFC400)),
                  const SizedBox(width: 8),
                  Text(
                    'Топ пользователей',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                'Рейтинг по лайкам публикаций',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: users.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final u = users[index];
                    return _TopUserTile(
                      rank: index + 1,
                      user: u,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopUserTile extends StatelessWidget {
  const _TopUserTile({
    required this.rank,
    required this.user,
  });

  final int rank;
  final TopUserRankEntity user;

  Color _rankColor(int r) {
    if (r == 1) return const Color(0xFFFFD54F);
    if (r == 2) return const Color(0xFFCFD8DC);
    if (r == 3) return const Color(0xFFFFB74D);
    return Colors.white.withValues(alpha: 0.85);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          final auth = context.read<AuthBloc>().state;
          final myId = auth is AuthAuthenticated ? auth.user.id : null;
          if (myId != null && myId == user.userId) {
            context.push('/home/profile');
            return;
          }
          context.push('/profile/${user.userId}');
        },
        child: Ink(
          width: 92,
          height: 128,
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: SizedBox(
              width: 76,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#$rank',
                    style: TextStyle(
                      color: _rankColor(rank),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  CachedAvatar(
                    imageUrl: user.avatarUrl,
                    radius: 16,
                    fallbackText: user.name,
                    enableLightboxOnTap: false,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatCompactCount(user.totalLikes)} лайков',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
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

class _NotificationTile extends StatefulWidget {
  const _NotificationTile({
    required this.row,
    required this.relativeTime,
    required this.mergedNames,
    required this.actionText,
    required this.displayBody,
    required this.accent,
    required this.icon,
    required this.onOpen,
    required this.showCommentActions,
    this.onReply,
    this.onLikeComment,
    this.commentId,
  });

  final _ActivityRow row;
  final String relativeTime;
  final String mergedNames;
  final String actionText;
  final String displayBody;
  final Color accent;
  final IconData icon;
  final VoidCallback onOpen;
  final bool showCommentActions;
  final VoidCallback? onReply;
  final Future<void> Function()? onLikeComment;
  final String? commentId;

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  bool _heartFilled = false;
  bool _likeStateReady = false;
  bool _likeBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLikeFromServer());
  }

  @override
  void didUpdateWidget(covariant _NotificationTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentId != widget.commentId ||
        oldWidget.row.primary.id != widget.row.primary.id ||
        oldWidget.row.primary.type != widget.row.primary.type) {
      _likeStateReady = false;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _loadLikeFromServer());
    }
  }

  Future<void> _loadLikeFromServer() async {
    final cid = widget.commentId?.trim();
    if (!widget.showCommentActions ||
        cid == null ||
        cid.isEmpty ||
        widget.onLikeComment == null) {
      if (mounted) setState(() => _likeStateReady = true);
      return;
    }
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      if (mounted) {
        setState(() {
          _heartFilled = false;
          _likeStateReady = true;
        });
      }
      return;
    }
    final postRepo = context.read<PostRepository>();
    final commentsRepo = context.read<CommentsRepository>();
    try {
      final type = widget.row.primary.type;
      final liked = type == 'post_comment'
          ? await postRepo.isPostCommentLikedOwn(cid, auth.user.id)
          : type == 'product_comment'
              ? await commentsRepo.isProductCommentLikedOwn(cid, auth.user.id)
              : false;
      if (mounted) {
        setState(() {
          _heartFilled = liked;
          _likeStateReady = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _likeStateReady = true);
    }
  }

  Future<void> _onHeartPressed() async {
    if (widget.onLikeComment == null || _likeBusy) return;
    setState(() => _likeBusy = true);
    try {
      await widget.onLikeComment!();
      if (mounted) setState(() => _heartFilled = !_heartFilled);
    } catch (_) {
      /* сообщение уже в родителе */
    } finally {
      if (mounted) setState(() => _likeBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.row.primary;
    final anyUnread = widget.row.anyUnread;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: !anyUnread
              ? ThemedContentSurface.scaffoldElevated
              : scheme.primaryContainer.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: !anyUnread
                ? Colors.black.withValues(alpha: 0.07)
                : widget.accent.withValues(alpha: 0.22),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: anyUnread ? 0.07 : 0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
              spreadRadius: -4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: widget.onOpen,
              borderRadius: BorderRadius.vertical(
                top: const Radius.circular(18),
                bottom: Radius.circular(
                  widget.showCommentActions ? 0 : 18,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NotificationSubjectThumb(item: item),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.35,
                                color: ThemedContentSurface.profileTextPrimary,
                              ),
                              children: [
                                TextSpan(
                                  text: widget.mergedNames,
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                TextSpan(
                                  text: ' ${widget.actionText}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: ThemedContentSurface.profileTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.displayBody.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.displayBody,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: ThemedContentSurface.profileTextPrimary,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            widget.relativeTime,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: ThemedContentSurface.profileTextSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _RightActorAvatars(
                      members: widget.row.members,
                      accent: widget.accent,
                      icon: widget.icon,
                    ),
                    if (anyUnread) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.45),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.showCommentActions) ...[
              Divider(
                height: 1,
                thickness: 0.5,
                color: Colors.black.withValues(alpha: 0.08),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 6, 6),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: widget.onReply,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: scheme.onSurface.withValues(alpha: 0.75),
                      ),
                      child: const Text(
                        'Ответить',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (!_likeStateReady &&
                        widget.onLikeComment != null)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (widget.onLikeComment != null)
                      IconButton(
                        onPressed: _likeBusy ? null : _onHeartPressed,
                        icon: Icon(
                          _heartFilled
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 22,
                          color: _heartFilled
                              ? const Color(0xFFE91E63)
                              : scheme.onSurface.withValues(alpha: 0.55),
                        ),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 40, minHeight: 40),
                      )
                    else
                      Tooltip(
                        message:
                            'Обновите базу (comment_id) или откройте пост и поставьте лайк под комментарием',
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Icon(
                            Icons.favorite_border_rounded,
                            size: 22,
                            color: scheme.onSurface.withValues(alpha: 0.28),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// До 3 аватаров справа (новые события — ближе к краю).
class _RightActorAvatars extends StatelessWidget {
  const _RightActorAvatars({
    required this.members,
    required this.accent,
    required this.icon,
  });

  final List<NotificationEntity> members;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    const maxShow = 3;
    final seen = <String>{};
    final ordered = <NotificationEntity>[];
    for (final m in members) {
      final id = m.actorId ?? m.id;
      if (seen.add(id)) ordered.add(m);
      if (ordered.length >= maxShow) break;
    }
    if (ordered.isEmpty) {
      return const SizedBox(width: 28);
    }
    final n = ordered.length;
    final w = 26.0 + (n - 1) * 14.0;
    return SizedBox(
      width: w,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          for (var i = 0; i < n; i++)
            Positioned(
              right: i * 14.0,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CachedAvatar(
                    imageUrl: ordered[i].actorAvatarUrl,
                    radius: 22,
                    fallbackText: ordered[i].actorName ?? '?',
                  ),
                  if (i == 0)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: ThemedContentSurface.scaffoldElevated,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Icon(icon, size: 12, color: accent),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Квадратное превью поста/объявления слева.
class _NotificationSubjectThumb extends StatelessWidget {
  const _NotificationSubjectThumb({required this.item});

  final NotificationEntity item;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.subjectImageUrl?.trim();
    final video = item.subjectVideoUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final hasVideo = !hasImage && video != null && video.isNotEmpty;
    final dpr = MediaQuery.devicePixelRatioOf(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 52,
        height: 52,
        child: ColoredBox(
          color: Colors.grey.shade200,
          child: hasImage
              ? CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: (52 * dpr).round(),
                  memCacheHeight: (52 * dpr).round(),
                  placeholder: (context, url) => Center(
                    child: Icon(
                      Icons.image_outlined,
                      color: Colors.grey.shade400,
                      size: 24,
                    ),
                  ),
                  errorWidget: (context, url, error) => Icon(
                    Icons.broken_image_outlined,
                    color: Colors.grey.shade500,
                    size: 28,
                  ),
                )
              : hasVideo
                  ? ColoredBox(
                      color: Colors.black87,
                      child: Icon(
                        Icons.play_circle_fill_rounded,
                        color: Colors.white.withValues(alpha: 0.65),
                        size: 30,
                      ),
                    )
                  : Icon(
                      Icons.grid_on_rounded,
                      color: Colors.grey.shade400,
                      size: 26,
                    ),
        ),
      ),
    );
  }
}
