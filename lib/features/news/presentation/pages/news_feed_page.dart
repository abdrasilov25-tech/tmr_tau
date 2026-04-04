import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/media/cached_video_controller.dart';
import '../../../../core/widgets/app_loading.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../../core/widgets/double_tap_like_burst.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../post/presentation/widgets/post_author_follow_pill.dart';
import '../../../post/presentation/widgets/post_photo_gallery.dart';
import '../../../post/presentation/widgets/post_share_sheet.dart';
import '../bloc/news_bloc.dart';
import '../widgets/news_city_picker.dart';

class NewsFeedPage extends StatefulWidget {
  const NewsFeedPage({super.key});

  @override
  State<NewsFeedPage> createState() => _NewsFeedPageState();
}

class _NewsFeedPageState extends State<NewsFeedPage> {
  static const _cityPrefKey = 'news_selected_city';
  String? _selectedCity;

  @override
  void initState() {
    super.initState();
    _loadSavedCity();
  }

  Future<void> _loadSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_cityPrefKey);
    if (!mounted) return;
    setState(() => _selectedCity = saved);
    // Перезагружаем ленту с сохранённым городом
    final userId = _currentUserId(context);
    // ignore: use_build_context_synchronously
    context.read<NewsBloc>().add(
          NewsLoaded(currentUserId: userId, cityFilter: saved),
        );
  }

  String? _currentUserId(BuildContext context) {
    final authState = context.read<AuthBloc>().state;
    return authState is AuthAuthenticated
        ? authState.user.id
        : context.read<AuthRepository>().currentUser?.id;
  }

  Future<void> _openCityPicker(BuildContext context) async {
    final result = await showNewsCityPicker(
      context: context,
      currentCity: _selectedCity,
    );
    // null → пользователь закрыл шторку без выбора, ничего не меняем
    if (result == null || !mounted) return;

    final newCity = result.city; // null = «Весь Казахстан»
    final prefs = await SharedPreferences.getInstance();
    if (newCity == null) {
      await prefs.remove(_cityPrefKey);
    } else {
      await prefs.setString(_cityPrefKey, newCity);
    }

    if (!mounted) return;
    setState(() => _selectedCity = newCity);
    // ignore: use_build_context_synchronously
    final userId = _currentUserId(context);
    // ignore: use_build_context_synchronously
    context.read<NewsBloc>().add(
          NewsLoaded(currentUserId: userId, cityFilter: newCity),
        );
  }

  Future<void> _openAddNews(BuildContext context, String? userId) async {
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Войдите, чтобы опубликовать новость'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await context.push<PostEntity?>('/add-news');
    if (!context.mounted) return;
    context.read<NewsBloc>().add(
          NewsRefresh(currentUserId: userId, cityFilter: _selectedCity),
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final userId = authState is AuthAuthenticated
        ? authState.user.id
        : context.read<AuthRepository>().currentUser?.id;

    return Builder(
      builder: (nested) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F4F5),
          appBar: _NewsAppBar(
            onNearby: () => context.push('/nearby'),
            selectedCity: _selectedCity,
            onCityTap: () => _openCityPicker(context),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: _NewsComposer(
                  avatarUrl: authState is AuthAuthenticated
                      ? authState.user.avatarUrl
                      : null,
                  displayName: authState is AuthAuthenticated
                      ? (authState.user.name ?? authState.user.email)
                      : null,
                  isLoggedIn: userId != null,
                  selectedCity: _selectedCity,
                  onTap: () => _openAddNews(nested, userId),
                ),
              ),
              Expanded(
                child: BlocBuilder<NewsBloc, NewsState>(
                  builder: (context, state) {
                    if (state is NewsLoading) {
                      return const Center(child: AppLoading());
                    }
                    if (state is NewsFailure) {
                      return _ErrorView(
                        message: state.message,
                        onRetry: () => context
                            .read<NewsBloc>()
                            .add(NewsLoaded(
                              currentUserId: userId,
                              cityFilter: _selectedCity,
                            )),
                      );
                    }
                    if (state is NewsSuccess) {
                      Future<void> refresh() async {
                        context.read<NewsBloc>().add(
                              NewsRefresh(
                                currentUserId: userId,
                                cityFilter: _selectedCity,
                              ),
                            );
                      }

                      if (state.posts.isEmpty) {
                        return RefreshIndicator(
                          onRefresh: refresh,
                          child: _EmptyView(
                            onTap: () => _openAddNews(nested, userId),
                          ),
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: refresh,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 28),
                          itemCount:
                              state.posts.length + (state.hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index >= state.posts.length) {
                              context.read<NewsBloc>().add(
                                    NewsLoadMore(currentUserId: userId),
                                  );
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              );
                            }
                            final post = state.posts[index];
                            return _NewsPostCard(
                              post: post,
                              currentUserId: userId,
                              onFollow: userId != null &&
                                      userId != post.userId &&
                                      !post.isAnonymous
                                  ? () {
                                      context.read<NewsBloc>().add(
                                            NewsToggleFollow(
                                              followerId: userId,
                                              followingId: post.userId,
                                            ),
                                          );
                                    }
                                  : null,
                              onPollVote: userId == null
                                  ? null
                                  : (int optionIndex) {
                                      context.read<NewsBloc>().add(
                                            NewsVotePoll(
                                              postId: post.id,
                                              userId: userId,
                                              optionIndex: optionIndex,
                                            ),
                                          );
                                    },
                              onLike: () {
                                if (userId != null) {
                                  context.read<NewsBloc>().add(
                                        NewsToggleLike(
                                            postId: post.id,
                                            userId: userId),
                                      );
                                } else {
                                  _showLoginRequired(context);
                                }
                              },
                              onRepost: () {
                                if (userId != null) {
                                  context.read<NewsBloc>().add(
                                        NewsToggleRepost(
                                            postId: post.id,
                                            userId: userId),
                                      );
                                } else {
                                  _showLoginRequired(context);
                                }
                              },
                              onComment: () async {
                                final deleted = await context
                                    .push<bool>('/post/${post.id}',
                                        extra: post);
                                if (deleted == true &&
                                    context.mounted) {
                                  context.read<NewsBloc>().add(
                                        NewsRefresh(
                                          currentUserId: userId,
                                          cityFilter: _selectedCity,
                                        ),
                                      );
                                }
                              },
                              onShare: () async {
                                if (userId == null) {
                                  _showLoginRequired(context);
                                  return;
                                }
                                await showModalBottomSheet<void>(
                                  context: context,
                                  isScrollControlled: true,
                                  showDragHandle: true,
                                  builder: (_) => PostShareSheet(
                                    currentUserId: userId,
                                    post: post,
                                    onAddToStory: () async {},
                                  ),
                                );
                              },
                              onSave: () async {
                                if (userId == null) {
                                  _showLoginRequired(context);
                                  return;
                                }
                                try {
                                  await context
                                      .read<PostRepository>()
                                      .toggleSave(post.id, userId);
                                  if (!context.mounted) return;
                                  context.read<NewsBloc>().add(
                                        NewsRefresh(
                                          currentUserId: userId,
                                          cityFilter: _selectedCity,
                                        ),
                                      );
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text(post.isSavedByMe
                                        ? 'Удалено из сохранённого'
                                        : 'Сохранено'),
                                    behavior: SnackBarBehavior.floating,
                                  ));
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                    content:
                                        Text('Не удалось сохранить'),
                                    behavior: SnackBarBehavior.floating,
                                  ));
                                }
                              },
                              onOptionsPressed: () =>
                                  _showPostOptions(
                                context: context,
                                post: post,
                                currentUserId: userId,
                                onRefresh: () =>
                                    context.read<NewsBloc>().add(
                                          NewsRefresh(
                                            currentUserId: userId,
                                            cityFilter: _selectedCity,
                                          ),
                                        ),
                              ),
                            );
                          },
                        ),
                      );
                    }
                    return const Center(child: AppLoading());
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLoginRequired(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Войдите, чтобы продолжить'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showPostOptions({
    required BuildContext context,
    required PostEntity post,
    required String? currentUserId,
    required VoidCallback onRefresh,
  }) async {
    final isOwn = currentUserId != null && post.userId == currentUserId;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Author row
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      if (post.isAnonymous)
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.grey.shade300,
                          child: Icon(
                            Icons.visibility_off_outlined,
                            size: 18,
                            color: Colors.grey.shade700,
                          ),
                        )
                      else
                        CachedAvatar(
                          imageUrl: post.userAvatarUrl,
                          radius: 18,
                          fallbackText: post.userName ?? 'U',
                        ),
                      const SizedBox(width: 10),
                      Text(
                        post.isAnonymous
                            ? 'Анонимно'
                            : (post.userName ?? 'Пользователь'),
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                const SizedBox(height: 4),
                // Own post options
                if (isOwn) ...[
                  _OptionTile(
                    icon: Icons.edit_outlined,
                    label: 'Редактировать',
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      await context.push('/edit-post/${post.id}',
                          extra: post);
                      if (context.mounted) onRefresh();
                    },
                  ),
                ],
                _OptionTile(
                  icon: post.isSavedByMe
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                  label: post.isSavedByMe
                      ? 'Убрать из сохранённого'
                      : 'Сохранить',
                  onTap: () async {
                    Navigator.pop(sheetCtx);
                    if (currentUserId == null) {
                      _showLoginRequired(context);
                      return;
                    }
                    try {
                      await context
                          .read<PostRepository>()
                          .toggleSave(post.id, currentUserId);
                      if (!context.mounted) return;
                      onRefresh();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(post.isSavedByMe
                              ? 'Удалено из сохранённого'
                              : 'Сохранено'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (_) {}
                  },
                ),
                _OptionTile(
                  icon: Icons.link_rounded,
                  label: 'Копировать ссылку',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    Clipboard.setData(
                      ClipboardData(
                          text: 'https://tmrtau.kz/post/${post.id}'),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ссылка скопирована'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                // Other user options
                if (!isOwn) ...[
                  const Divider(height: 12),
                  _OptionTile(
                    icon: Icons.block_rounded,
                    label: 'Заблокировать автора',
                    color: Colors.red.shade600,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _confirmBlock(context, post);
                    },
                  ),
                  _OptionTile(
                    icon: Icons.flag_outlined,
                    label: 'Пожаловаться',
                    color: Colors.red.shade600,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _showReportSheet(context, post);
                    },
                  ),
                ],
                // Own delete
                if (isOwn) ...[
                  const Divider(height: 12),
                  _OptionTile(
                    icon: Icons.delete_outline_rounded,
                    label: 'Удалить публикацию',
                    color: Colors.red.shade600,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      _confirmDelete(
                        context: context,
                        post: post,
                        currentUserId: currentUserId,
                        onRefresh: onRefresh,
                      );
                    },
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete({
    required BuildContext context,
    required PostEntity post,
    required String currentUserId,
    required VoidCallback onRefresh,
  }) {
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Удалить публикацию?'),
        content:
            const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600),
            onPressed: () async {
              Navigator.pop(dlgCtx);
              try {
                await context
                    .read<PostRepository>()
                    .deletePost(post.id, currentUserId);
                if (!context.mounted) return;
                onRefresh();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Публикация удалена'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Не удалось удалить'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
  }

  void _confirmBlock(BuildContext context, PostEntity post) {
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text('Заблокировать ${post.userName ?? 'пользователя'}?'),
        content: const Text(
            'Вы больше не будете видеть его публикации.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600),
            onPressed: () {
              Navigator.pop(dlgCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${post.userName ?? 'Пользователь'} заблокирован'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
  }

  void _showReportSheet(BuildContext context, PostEntity post) {
    final reasons = [
      'Спам',
      'Оскорбительный контент',
      'Недостоверная информация',
      'Насилие или угрозы',
      'Другое',
    ];
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  'Причина жалобы',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Divider(height: 1),
              ...reasons.map(
                (r) => _OptionTile(
                  icon: Icons.flag_outlined,
                  label: r,
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Жалоба отправлена. Спасибо!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// AppBar
// ─────────────────────────────────────────────

class _NewsAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _NewsAppBar({
    required this.onNearby,
    required this.onCityTap,
    this.selectedCity,
  });
  final VoidCallback onNearby;
  final VoidCallback onCityTap;
  final String? selectedCity;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final cityLabel = selectedCity ?? 'Весь Казахстан';

    return AppBar(
      backgroundColor: const Color(0xFFF4F4F5),
      elevation: 0,
      scrolledUnderElevation: 0.5,
      title: Text(
        'Новости',
        style: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF0A0A0A),
          letterSpacing: -0.5,
        ),
      ),
      centerTitle: false,
      actions: [
        // Кнопка выбора города
        GestureDetector(
          onTap: onCityTap,
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selectedCity != null
                  ? Colors.black87
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selectedCity != null
                    ? Colors.black87
                    : Colors.grey.shade300,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 14,
                  color: selectedCity != null
                      ? Colors.white
                      : Colors.grey.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  cityLabel,
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selectedCity != null
                        ? Colors.white
                        : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.expand_more_rounded,
                  size: 14,
                  color: selectedCity != null
                      ? Colors.white70
                      : Colors.grey.shade500,
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Рядом',
          onPressed: onNearby,
          icon: Icon(Icons.near_me_rounded, color: Colors.grey.shade700),
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.black.withValues(alpha: 0.06)),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Composer — единая точка создания новости
// ─────────────────────────────────────────────

class _NewsComposer extends StatelessWidget {
  const _NewsComposer({
    required this.avatarUrl,
    required this.displayName,
    required this.isLoggedIn,
    required this.onTap,
    this.selectedCity,
  });

  final String? avatarUrl;
  final String? displayName;
  final bool isLoggedIn;
  final VoidCallback onTap;
  final String? selectedCity;

  @override
  Widget build(BuildContext context) {
    final name = displayName?.trim();
    final fallback = isLoggedIn
        ? (name != null && name.isNotEmpty
            ? name.substring(0, 1).toUpperCase()
            : '?')
        : '?';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                CachedAvatar(
                  imageUrl: avatarUrl,
                  radius: 22,
                  fallbackText: fallback,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Новая тема',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF0A0A0A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isLoggedIn
                            ? 'Что нового в ${selectedCity ?? 'Казахстане'}? Текст, фото, опрос или место.'
                            : 'Войдите, чтобы публиковать',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          height: 1.3,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_note_rounded,
                  color: Colors.grey.shade700,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Карточка поста
// ─────────────────────────────────────────────

class _NewsPostCard extends StatelessWidget {
  const _NewsPostCard({
    required this.post,
    required this.currentUserId,
    this.onFollow,
    this.onPollVote,
    required this.onLike,
    required this.onRepost,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onOptionsPressed,
  });

  final PostEntity post;
  final String? currentUserId;
  final VoidCallback? onFollow;
  final void Function(int optionIndex)? onPollVote;
  final VoidCallback onLike;
  final VoidCallback onRepost;
  final VoidCallback onComment;
  final Future<void> Function() onShare;
  final Future<void> Function() onSave;
  final VoidCallback onOptionsPressed;

  @override
  Widget build(BuildContext context) {
    final anon = post.isAnonymous;
    final displayName =
        anon ? 'Анонимно' : (post.userName ?? 'Житель');
    final avatarFallback = anon ? '?' : displayName;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06), width: 1),
        ),
      ),
      child: InkWell(
        onTap: onComment,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column: avatar + thread line
              _AvatarColumn(
                avatarUrl: anon ? null : post.userAvatarUrl,
                userName: avatarFallback,
                userId: post.userId,
                commentsCount: post.commentsCount,
                isAnonymous: anon,
                openProfile: !anon,
                isOfficialPage: !anon && post.authorOfficialPageActive,
              ),
              const SizedBox(width: 12),
              // Right column: content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: name + time + three dots
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: anon
                                ? null
                                : () =>
                                    context.push('/profile/${post.userId}'),
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: const Color(0xFF0A0A0A),
                                    ),
                                  ),
                                ),
                                if (!anon && post.authorOfficialPageActive) ...[
                                  const SizedBox(width: 4),
                                  const VerifiedBadge(size: 16),
                                ],
                                if (post.isPromoted) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.shade700,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'PRO',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 8),
                                Text(
                                  _formatTime(post.createdAt),
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (onFollow != null) ...[
                          const SizedBox(width: 6),
                          PostAuthorFollowPill(
                            isFollowing: post.isFollowingAuthor,
                            onTap: onFollow!,
                            compact: true,
                          ),
                        ],
                        // Three dots
                        GestureDetector(
                          onTap: onOptionsPressed,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.more_horiz,
                              size: 20,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (post.locationLabel != null &&
                        post.locationLabel!.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 15,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              post.locationLabel!.trim(),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Caption
                    if (post.caption.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _ExpandableCaption(caption: post.caption),
                    ],
                    if (post.hasPoll) ...[
                      const SizedBox(height: 10),
                      _NewsPollBlock(
                        post: post,
                        onVote: onPollVote,
                      ),
                    ],
                    // Media
                    if (post.videoUrl != null &&
                        post.videoUrl!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DoubleTapLikeBurst(
                        iconSize: 72,
                        onDoubleTapLike: onLike,
                        shouldTriggerLike: () => !post.isLikedByMe,
                        showPersistentLikeIndicator: true,
                        isLiked: post.isLikedByMe,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _PostVideoPlayer(
                              videoUrl: post.videoUrl!),
                        ),
                      ),
                    ] else if (post.displayImageUrls.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DoubleTapLikeBurst(
                        iconSize: 72,
                        onDoubleTapLike: onLike,
                        shouldTriggerLike: () => !post.isLikedByMe,
                        showPersistentLikeIndicator: true,
                        isLiked: post.isLikedByMe,
                        child: PostNetworkPhotoGallery(
                          urls: post.displayImageUrls,
                          height: post.displayImageUrls.length > 1
                              ? 280
                              : 260,
                          borderRadius: 12,
                          viewportFraction:
                              post.displayImageUrls.length > 1
                                  ? 0.92
                                  : 1,
                          enableTapToOpenFullscreen: false,
                        ),
                      ),
                    ],
                    // Action bar
                    const SizedBox(height: 10),
                    _ActionBar(
                      post: post,
                      onLike: onLike,
                      onComment: onComment,
                      onRepost: onRepost,
                      onShare: onShare,
                      onSave: onSave,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин';
    if (diff.inHours < 24) return '${diff.inHours} ч';
    if (diff.inDays < 7) return '${diff.inDays} дн';
    final months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} · $h:$m';
  }
}

// ─────────────────────────────────────────────
// Аватар + вертикальная нить (как в Threads)
// ─────────────────────────────────────────────

class _AvatarColumn extends StatelessWidget {
  const _AvatarColumn({
    required this.avatarUrl,
    required this.userName,
    required this.userId,
    required this.commentsCount,
    this.isAnonymous = false,
    this.openProfile = true,
    this.isOfficialPage = false,
  });

  final String? avatarUrl;
  final String userName;
  final String userId;
  final int commentsCount;
  final bool isAnonymous;
  final bool openProfile;
  final bool isOfficialPage;

  static const _goldGradient = [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFFD700)];

  @override
  Widget build(BuildContext context) {
    Widget avatar = isAnonymous
        ? CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey.shade300,
            child: Icon(
              Icons.visibility_off_outlined,
              size: 20,
              color: Colors.grey.shade700,
            ),
          )
        : CachedAvatar(
            imageUrl: avatarUrl,
            radius: 20,
            fallbackText: userName,
          );

    if (isOfficialPage && !isAnonymous) {
      avatar = Container(
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: _goldGradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: avatar,
      );
    }

    return Column(
      children: [
        GestureDetector(
          onTap: openProfile ? () => context.push('/profile/$userId') : null,
          child: avatar,
        ),
        if (commentsCount > 0) ...[
          const SizedBox(height: 4),
          Container(
            width: 2,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Опрос в карточке новости
// ─────────────────────────────────────────────

class _NewsPollBlock extends StatelessWidget {
  const _NewsPollBlock({
    required this.post,
    this.onVote,
  });

  final PostEntity post;
  final void Function(int optionIndex)? onVote;

  void _showVoters(BuildContext context, int optionIndex, String optionText) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PollVotersSheet(
        postId: post.id,
        optionIndex: optionIndex,
        optionText: optionText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = post.pollQuestion ?? '';
    final opts = post.pollOptions;
    if (opts.length < 2) return const SizedBox.shrink();
    final counts = post.pollVoteCounts.length == opts.length
        ? post.pollVoteCounts
        : List<int>.filled(opts.length, 0, growable: false);
    final total = counts.fold<int>(0, (a, b) => a + b);
    final my = post.myPollVoteIndex;
    final hasVoted = my != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F4F5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            q,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              height: 1.25,
              color: const Color(0xFF0A0A0A),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < opts.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onVote == null ? null : () => onVote!(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                opts[i],
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: const Color(0xFF0A0A0A),
                                ),
                              ),
                            ),
                            if (my == i)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 18,
                                color: Colors.blue.shade700,
                              ),
                          ],
                        ),
                        if (total > 0) ...[
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: counts[i] / total,
                              minHeight: 5,
                              backgroundColor: Colors.grey.shade200,
                              color: Colors.blue.shade400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: hasVoted && counts[i] > 0
                                ? () => _showVoters(context, i, opts[i])
                                : null,
                            child: Row(
                              children: [
                                Text(
                                  '${counts[i]} голосов · ${total == 0 ? 0 : ((counts[i] / total) * 100).round()}%',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (hasVoted && counts[i] > 0) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.people_outline,
                                    size: 13,
                                    color: Colors.blue.shade400,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (onVote == null)
            Text(
              'Войдите, чтобы голосовать',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          if (hasVoted && total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Нажми на счётчик голосов чтобы увидеть кто голосовал',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Шит с проголосовавшими за вариант опроса
// ─────────────────────────────────────────────

class _PollVotersSheet extends StatefulWidget {
  const _PollVotersSheet({
    required this.postId,
    required this.optionIndex,
    required this.optionText,
  });

  final String postId;
  final int optionIndex;
  final String optionText;

  @override
  State<_PollVotersSheet> createState() => _PollVotersSheetState();
}

class _PollVotersSheetState extends State<_PollVotersSheet> {
  List<({String userId, String name, String? avatarUrl})>? _voters;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = context.read<PostRepository>();
      final result = await repo.fetchPollVoters(
        postId: widget.postId,
        optionIndex: widget.optionIndex,
      );
      if (mounted) setState(() => _voters = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final voters = _voters;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Голосовали за:',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '"${widget.optionText}"',
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0A0A0A),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? Center(
                    child: Text(
                      'Ошибка загрузки',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : voters == null
                    ? const Center(child: CircularProgressIndicator())
                    : voters.isEmpty
                        ? Center(
                            child: Text(
                              'Никто ещё не голосовал',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.builder(
                            controller: sc,
                            itemCount: voters.length,
                            itemBuilder: (_, i) {
                              final v = voters[i];
                              return ListTile(
                                leading: CachedAvatar(
                                  imageUrl: v.avatarUrl,
                                  radius: 18,
                                  fallbackText: v.name,
                                ),
                                title: Text(
                                  v.name,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pop(context);
                                  context.push('/profile/${v.userId}');
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Раскрываемый текст поста
// ─────────────────────────────────────────────

class _ExpandableCaption extends StatefulWidget {
  const _ExpandableCaption({required this.caption});
  final String caption;

  @override
  State<_ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<_ExpandableCaption> {
  bool _expanded = false;
  static const _maxLines = 4;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.caption,
          maxLines: _expanded ? null : _maxLines,
          overflow:
              _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
          style: GoogleFonts.poppins(
            fontSize: 14,
            height: 1.45,
            color: Colors.black87,
          ),
        ),
        if (!_expanded && widget.caption.length > 200) ...[
          const SizedBox(height: 2),
          GestureDetector(
            onTap: () => setState(() => _expanded = true),
            child: Text(
              'ещё',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Action bar: лайк, комментарий, репост, поделиться, сохранить
// ─────────────────────────────────────────────

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onRepost,
    required this.onShare,
    required this.onSave,
  });

  final PostEntity post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final Future<void> Function() onShare;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Лайк
        _ActionBtn(
          icon: post.isLikedByMe
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          count: post.likesCount,
          color: post.isLikedByMe ? Colors.red : Colors.grey.shade600,
          onTap: onLike,
        ),
        const SizedBox(width: 18),
        // Комментарий
        _ActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          count: post.commentsCount,
          color: Colors.grey.shade600,
          onTap: onComment,
        ),
        const SizedBox(width: 18),
        // Репост
        _ActionBtn(
          icon: Icons.repeat_rounded,
          count: post.repostsCount,
          color: post.isRepostedByMe
              ? const Color(0xFF00B96B)
              : Colors.grey.shade600,
          onTap: onRepost,
        ),
        const SizedBox(width: 18),
        // Поделиться
        GestureDetector(
          onTap: onShare,
          child: Icon(
            Icons.send_rounded,
            size: 20,
            color: Colors.grey.shade600,
          ),
        ),
        const Spacer(),
        // Сохранить
        GestureDetector(
          onTap: onSave,
          child: Icon(
            post.isSavedByMe
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            size: 20,
            color: post.isSavedByMe
                ? Colors.black87
                : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Text(
              _fmt(count),
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────
// Строка меню (bottom sheet option)
// ─────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black87;
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: c,
        ),
      ),
      onTap: onTap,
      dense: true,
    );
  }
}

// ─────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
      children: [
        Icon(Icons.article_outlined, size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 24),
        Text(
          'Пока нет новостей',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Будьте первым — расскажите что происходит в городе',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Colors.grey.shade500,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        Center(
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0A0A0A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Text(
              'Создать новость',
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
// Error state
// ─────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.black87),
              child: Text(
                'Повторить',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Video player
// ─────────────────────────────────────────────

class _PostVideoPlayer extends StatefulWidget {
  const _PostVideoPlayer({required this.videoUrl});
  final String videoUrl;

  @override
  State<_PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<_PostVideoPlayer> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final c = await createCachedVideoController(widget.videoUrl);
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return GestureDetector(
      onTap: () => setState(
          () => c.value.isPlaying ? c.pause() : c.play()),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: c.value.aspectRatio,
            child: VideoPlayer(c),
          ),
          if (!c.value.isPlaying)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 44),
            ),
        ],
      ),
    );
  }
}
