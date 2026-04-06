import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/products/deleted_product_bus.dart';
import '../../../../core/utils/phone_launch.dart';
import '../../../feed/presentation/bloc/feed_bloc.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/double_tap_like_burst.dart';
import '../widgets/product_image_gallery.dart';
import '../widgets/product_overflow_sheet.dart';
import '../widgets/product_promo_badges.dart';
import '../widgets/product_promotion_sheet.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../comments/domain/entities/product_comment_entity.dart';
import '../../../comments/domain/repositories/comments_repository.dart';
import '../../../chat/presentation/widgets/start_chat_button.dart';
import '../../../chat/presentation/widgets/unified_message_composer_bar.dart';
import '../../../orders/domain/repositories/orders_repository.dart';
import '../../domain/entities/product_entity.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/value_objects/product_price_insight.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({
    super.key,
    required this.product,
    required this.commentsRepository,
    this.productRepository,
    this.mentionPrefix,
  });

  final ProductEntity product;
  final CommentsRepository commentsRepository;
  final ProductRepository? productRepository;
  /// Подставить в поле комментария (например `@Имя ` из уведомления).
  final String? mentionPrefix;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  late ProductEntity _product;
  List<ProductCommentEntity> _comments = [];
  bool _commentsLoading = true;
  final _commentController = TextEditingController();
  late final ValueNotifier<bool> _commentHasText;
  bool _sending = false;
  bool _isInFavorites = false;
  bool _favoriteToggling = false;
  ProductPriceInsight? _priceInsight;
  bool _priceInsightReady = false;

  @override
  void initState() {
    super.initState();
    _commentHasText = ValueNotifier(false);
    _commentController.addListener(() {
      _commentHasText.value = _commentController.text.trim().isNotEmpty;
    });
    _product = widget.product;
    _loadComments();
    _loadIsInFavorites();
    // Счётчик просмотров — один запрос после первого кадра (не в build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bumpViewCount();
      _loadPriceInsight();
    });
    final mention = widget.mentionPrefix?.trim();
    if (mention != null && mention.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final at = mention.startsWith('@') ? mention : '@$mention';
        _commentController.text = '$at ';
        _commentController.selection =
            TextSelection.collapsed(offset: _commentController.text.length);
      });
    }
  }

  /// RPC `increment_product_view` + обновление модели (число просмотров для статистики).
  Future<void> _bumpViewCount() async {
    final repo = widget.productRepository;
    if (repo == null) return;
    try {
      await repo.incrementProductView(_product.id);
      if (!mounted) return;
      final authState = context.read<AuthBloc>().state;
      final uid = authState is AuthAuthenticated ? authState.user.id : null;
      final refreshed =
          await repo.getProductById(_product.id, currentUserId: uid);
      if (refreshed != null && mounted) {
        setState(() => _product = refreshed);
      }
    } catch (e) { debugPrint('$e'); }
  }

  Future<void> _loadPriceInsight() async {
    final repo = widget.productRepository;
    final cid = _product.categoryId?.trim();
    if (repo == null || cid == null || cid.isEmpty) {
      if (mounted) setState(() => _priceInsightReady = true);
      return;
    }
    try {
      final insight = await repo.getCategoryPriceInsight(
        excludeProductId: _product.id,
        categoryId: cid,
        subjectPrice: _product.price,
        isGiveaway: _product.isGiveaway,
      );
      if (!mounted) return;
      setState(() {
        _priceInsight = insight;
        _priceInsightReady = true;
      });
    } catch (e) {
      if (mounted) setState(() => _priceInsightReady = true);
    }
  }

  Future<void> _refreshAfterPromo() async {
    final repo = widget.productRepository;
    if (repo == null) return;
    final authState = context.read<AuthBloc>().state;
    final uid = authState is AuthAuthenticated ? authState.user.id : null;
    final p = await repo.getProductById(_product.id, currentUserId: uid);
    if (p != null && mounted) setState(() => _product = p);
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
    } catch (e) { debugPrint('$e'); }
  }

  @override
  void dispose() {
    _commentHasText.dispose();
    _commentController.dispose();
    super.dispose();
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
    } catch (e) {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  Future<void> _sendComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    _commentController.clear();
    _commentHasText.value = false;
    await _submitProductComment(text);
  }

  Future<void> _sendQuickProductComment(String emoji) async {
    final text = emoji.trim();
    if (text.isEmpty) return;
    await _submitProductComment(text);
  }

  Future<void> _submitProductComment(String text) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы оставить комментарий')),
      );
      return;
    }
    setState(() => _sending = true);
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

  Future<void> _createSafeOrder() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы оформить безопасную сделку')),
      );
      return;
    }
    final buyerId = authState.user.id;
    if (buyerId == _product.sellerId) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Купить безопасно'),
        content: Text(
          'Сделка пройдет через защиту платформы.\n'
          'Комиссия сервиса: 4%.\n'
          'Сумма: ${_product.price.toStringAsFixed(0)} ₸.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Создать сделку'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await context.read<OrdersRepository>().createSafeOrder(
            buyerId: buyerId,
            sellerId: _product.sellerId,
            productId: _product.id,
            productTitle: _product.title,
            amountKzt: _product.price,
            commissionPercent: 4,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Безопасная сделка создана. Следите за статусом в заказах'),
        ),
      );
      context.push('/orders');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать сделку: $e')),
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
            actions: [
              if (!isOwner)
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  tooltip: 'Ещё',
                  onPressed: () =>
                      showProductOverflowSheet(context, product: _product),
                ),
              if (isOwner) ...[
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
              ],
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: DoubleTapLikeBurst(
                iconSize: 88,
                canDoubleTap: () {
                  if (authState is! AuthAuthenticated) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Войдите, чтобы добавить товар в избранное'),
                      ),
                    );
                    return false;
                  }
                  if (widget.productRepository == null || _favoriteToggling) {
                    return false;
                  }
                  return true;
                },
                onDoubleTapLike: _toggleFavorite,
                shouldTriggerLike: () => !_isInFavorites,
                showPersistentLikeIndicator: true,
                isLiked: _isInFavorites,
                child: ProductImageGallery(
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
                  const SizedBox(height: 14),
                  _SellerHighlightCard(product: _product),
                  const SizedBox(height: 12),
                  Text(
                    _product.priceFormatted,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: _product.isGiveaway
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFFE31E24),
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    child: !_priceInsightReady
                        ? const SizedBox(
                            key: ValueKey('pi_loading'),
                            height: 8,
                          )
                        : _priceInsight == null
                            ? const SizedBox(
                                key: ValueKey('pi_none'),
                                height: 0,
                              )
                            : Padding(
                                key: ValueKey(_priceInsight!.headline),
                                padding: const EdgeInsets.only(top: 10),
                                child: _ProductDetailPriceInsightCard(
                                  insight: _priceInsight!,
                                ),
                              ),
                  ),
                  if (_product.isGiveaway || _product.isNegotiable) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (_product.isGiveaway)
                          Chip(
                            label: const Text('Отдам даром'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelStyle:
                                Theme.of(context).textTheme.labelMedium,
                          ),
                        if (_product.isNegotiable)
                          Chip(
                            label: const Text('Есть торг'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            labelStyle:
                                Theme.of(context).textTheme.labelMedium,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ProductPromoBadges(product: _product),
                  ),
                  if (isOwner) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await ProductPromotionSheet.show(
                          context,
                          product: _product,
                          onPromotionActivated: _refreshAfterPromo,
                        );
                      },
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('Продвижение и статистика'),
                    ),
                  ],
                  if (isOwner && _product.hasActiveStatsAccess) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.visibility_outlined),
                        title: Text('Просмотров: ${_product.viewCount}'),
                        subtitle: const Text(
                          'Доступ к статистике по платной подписке',
                        ),
                      ),
                    ),
                  ],
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
                  if (!isOwner) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _createSafeOrder,
                      icon: const Icon(Icons.shield_outlined),
                      label: const Text('Купить безопасно'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ],
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
                    ChatQuickEmojiStrip(
                      compact: true,
                      onEmojiTap: (e) => unawaited(_sendQuickProductComment(e)),
                    ),
                    UnifiedMessageComposerBar(
                      controller: _commentController,
                      hintText: 'Сообщение',
                      textHasContent: _commentHasText,
                      onSend: _sendComment,
                      onChanged: (_) {},
                      showVoiceVideoWhenEmpty: false,
                      onAttachment: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Фото к комментарию скоро. Пока — текст и эмодзи.',
                            ),
                          ),
                        );
                      },
                      onEmojiToggle: () {
                        FocusScope.of(context).unfocus();
                        showCommentEmojiPickerSheet(
                          context,
                          onEmoji: (emoji) {
                            final c = _commentController;
                            c.text = c.text + emoji;
                            c.selection =
                                TextSelection.collapsed(offset: c.text.length);
                            _commentHasText.value = c.text.trim().isNotEmpty;
                          },
                        );
                      },
                      sending: _sending,
                      onFieldTap: () {},
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

class _SellerHighlightCard extends StatelessWidget {
  const _SellerHighlightCard({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = product.sellerName?.trim().isNotEmpty == true
        ? product.sellerName!.trim()
        : 'Продавец';
    return Material(
      color: theme.colorScheme.surfaceContainerLowest,
      elevation: 0,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => context.push('/profile/${product.sellerId}'),
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                theme.colorScheme.surfaceContainerLowest,
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CachedAvatar(
                  imageUrl: product.sellerAvatarUrl,
                  radius: 26,
                  fallbackText: name,
                  enableLightboxOnTap: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Продаёт',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (product.sellerIsVerified) ...[
                            const SizedBox(width: 6),
                            const VerifiedBadge(size: 20),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductDetailPriceInsightCard extends StatelessWidget {
  const _ProductDetailPriceInsightCard({required this.insight});

  final ProductPriceInsight insight;

  Color _bg(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (insight.tone) {
      InsightTone.favorable => const Color(0xFFE8F5E9),
      InsightTone.neutral => scheme.surfaceContainerHighest,
      InsightTone.caution => const Color(0xFFFFF3E0),
    };
  }

  Color _fg() {
    return switch (insight.tone) {
      InsightTone.favorable => const Color(0xFF1B5E20),
      InsightTone.neutral => const Color(0xFF424242),
      InsightTone.caution => const Color(0xFFE65100),
    };
  }

  @override
  Widget build(BuildContext context) {
    final fg = _fg();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: fg.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            switch (insight.tone) {
              InsightTone.favorable => Icons.lightbulb_outline_rounded,
              InsightTone.caution => Icons.info_outline_rounded,
              InsightTone.neutral => Icons.insights_outlined,
            },
            color: fg,
            size: 26,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight.headline,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (insight.detail != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    insight.detail!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: fg.withValues(alpha: 0.9),
                          height: 1.3,
                        ),
                  ),
                ],
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
