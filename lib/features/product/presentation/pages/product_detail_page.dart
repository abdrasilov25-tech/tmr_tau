import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/products/deleted_product_bus.dart';
import '../../../../core/utils/phone_launch.dart';
import '../../../feed/presentation/bloc/feed_bloc.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../widgets/product_image_gallery.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../comments/domain/entities/product_comment_entity.dart';
import '../../../comments/domain/repositories/comments_repository.dart';
import '../../../chat/presentation/widgets/start_chat_button.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.product,
    required this.commentsRepository,
    this.productRepository,
  });

  final ProductEntity product;
  final CommentsRepository commentsRepository;
  final ProductRepository? productRepository;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late ProductEntity _product;
  List<ProductCommentEntity> _comments = [];
  bool _commentsLoading = true;
  final _commentController = TextEditingController();
  bool _sending = false;
  bool _isInFavorites = false;
  bool _favoriteToggling = false;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _loadComments();
    _loadIsInFavorites();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  /// Проверяем, есть ли товар уже в избранном (чтобы показать «В избранном»).
  Future<void> _loadIsInFavorites() async {
    final repo = widget.productRepository;
    final authState = context.read<AuthBloc>().state;
    if (repo == null || authState is! AuthAuthenticated) return;
    try {
      final list = await repo.getFavorites(authState.user.id);
      if (mounted) {
        setState(() => _isInFavorites = list.any((p) => p.id == _product.id));
      }
    } catch (_) {}
  }

  Future<void> _loadComments() async {
    try {
      final list = await widget.commentsRepository.getProductComments(_product.id);
      if (mounted) {
        setState(() {
        _comments = list;
        _commentsLoading = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы оставить комментарий')),
      );
      return;
    }
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _commentController.clear();
    try {
      await widget.commentsRepository.addComment(
            productId: _product.id,
            userId: authState.user.id,
            text: text,
          );
      if (!mounted) return;
      await _loadComments();
    } catch (e) {
      if (mounted) {
        final msg = e is PostgrestException ? e.message : e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(ProductCommentEntity comment) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated || authState.user.id != comment.userId) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить комментарий?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await widget.commentsRepository.deleteComment(comment.id, authState.user.id);
      if (!mounted) return;
      setState(() => _comments = _comments.where((c) => c.id != comment.id).toList());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
    }
  }

  Future<void> _toggleFavorite() async {
    final repo = widget.productRepository;
    final authState = context.read<AuthBloc>().state;
    if (repo == null || authState is! AuthAuthenticated) return;
    setState(() => _favoriteToggling = true);
    try {
      await repo.toggleFavorite(_product.id, authState.user.id);
      if (mounted) {
        setState(() {
          _isInFavorites = !_isInFavorites;
          _favoriteToggling = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isInFavorites ? 'Добавлено в избранное' : 'Удалено из избранного'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _favoriteToggling = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка: $e')));
      }
    }
  }

  Future<void> _deleteProduct(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить товар?'),
        content: const Text(
          'Товар будет удалён без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.read<ProductRepository>().deleteProduct(_product.id);
      notifyProductDeleted(_product.id);
      if (context.mounted) {
        context.read<FeedBloc>().add(FeedProductRemoved(productId: _product.id));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Товар удалён')),
      );
      context.go('/home/feed');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthBloc>().state;
    final isOwner = authState is AuthAuthenticated &&
        authState.user.id == _product.sellerId;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            actions: isOwner
                ? [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () async {
                        final updated = await context.push<ProductEntity?>(
                          '/product/${_product.id}/edit',
                          extra: _product,
                        );
                        if (updated != null && mounted) {
                          setState(() => _product = updated);
                        }
                      },
                      tooltip: 'Редактировать',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteProduct(context),
                      tooltip: 'Удалить',
                    ),
                  ]
                : null,
            flexibleSpace: FlexibleSpaceBar(
              background: ProductImageGallery(
                key: ValueKey<String>(_product.imageUrls.join('|')),
                imageUrls: _product.imageUrls.isNotEmpty
                    ? _product.imageUrls
                    : (_product.imageUrl.isNotEmpty
                        ? <String>[_product.imageUrl]
                        : <String>[]),
                height: 320,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _product.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _product.priceFormatted,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => context.push('/profile/${_product.sellerId}'),
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      children: [
                        CachedAvatar(
                          imageUrl: _product.sellerAvatarUrl,
                          radius: 24,
                          fallbackText: _product.sellerName,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _product.sellerName ?? 'Продавец',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  if (_product.sellerIsVerified) ...[
                                    const SizedBox(width: 6),
                                    const VerifiedBadge(size: 20),
                                  ],
                                ],
                              ),
                              Text(
                                'Перейти в профиль',
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Описание',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _product.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_product.contactPhone != null &&
                      _product.contactPhone!.trim().isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _ProductContactPhoneSection(
                      phone: _product.contactPhone!.trim(),
                      isOwner: isOwner,
                    ),
                  ],
                  const SizedBox(height: 24),
                  StartChatButton(
                    peerId: _product.sellerId,
                    peerName: _product.sellerName ?? 'Продавец',
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _favoriteToggling || widget.productRepository == null
                        ? null
                        : _toggleFavorite,
                    icon: Icon(
                      _isInFavorites ? Icons.favorite : Icons.favorite_border,
                      size: 22,
                      color: _isInFavorites ? Colors.white : null,
                    ),
                    label: Text(
                      _isInFavorites ? 'В избранном' : 'Сохранить в избранное',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: _isInFavorites ? Colors.red : null,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    'Комментарии (${_comments.length})',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (_commentsLoading)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else if (_comments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          'Пока нет комментариев',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ),
                    )
                  else
                    ..._comments.map(
                      (c) => _ProductCommentTile(
                        comment: c,
                        currentUserId: authState is AuthAuthenticated ? authState.user.id : null,
                        onDelete: () => _deleteComment(c),
                      ),
                    ),
                  if (authState is AuthAuthenticated) ...[
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            decoration: const InputDecoration(
                              hintText: 'Написать комментарий...',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            maxLines: 2,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _sendComment(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _sending ? null : _sendComment,
                          icon: _sending
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.send_outlined),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Телефон как в OLX: покупатель сначала нажимает «Позвонить», затем видит номер.
class _ProductContactPhoneSection extends StatefulWidget {
  const _ProductContactPhoneSection({
    required this.phone,
    required this.isOwner,
  });

  final String phone;
  final bool isOwner;

  @override
  State<_ProductContactPhoneSection> createState() =>
      _ProductContactPhoneSectionState();
}

class _ProductContactPhoneSectionState extends State<_ProductContactPhoneSection> {
  bool _revealed = false;

  Future<void> _dial() async {
    final ok = await launchPhoneCall(widget.phone);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть набор номера'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.isOwner) {
      return Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        child: ListTile(
          leading: Icon(Icons.phone_in_talk_outlined, color: scheme.primary),
          title: const Text('Телефон в объявлении'),
          subtitle: Text(
            widget.phone,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      );
    }

    if (_revealed) {
      return Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Номер продавца',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                widget.phone,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      letterSpacing: 0.5,
                    ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _dial,
                icon: const Icon(Icons.phone),
                label: const Text('Позвонить'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: () => setState(() => _revealed = true),
      icon: const Icon(Icons.phone_callback_outlined),
      label: const Text('Позвонить'),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    );
  }
}

class _ProductCommentTile extends StatelessWidget {
  const _ProductCommentTile({
    required this.comment,
    required this.currentUserId,
    required this.onDelete,
  });

  final ProductCommentEntity comment;
  final String? currentUserId;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isOwn = currentUserId == comment.userId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CachedAvatar(
            imageUrl: comment.userAvatarUrl,
            radius: 18,
            fallbackText: comment.userName ?? comment.userId,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.userName ?? 'Пользователь',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(comment.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (isOwn) ...[
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _timeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime);
  if (diff.inMinutes < 1) return 'только что';
  if (diff.inMinutes < 60) return '${diff.inMinutes} мин';
  if (diff.inHours < 24) return '${diff.inHours} ч';
  if (diff.inDays < 7) return '${diff.inDays} дн';
  return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
}
