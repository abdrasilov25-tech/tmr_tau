import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../controllers/search_paging_controller.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.postRepository,
    required this.productRepository,
  });

  final PostRepository postRepository;
  final ProductRepository productRepository;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  late final SearchPagingController _pagingController;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _pagingController = SearchPagingController(
      postRepository: widget.postRepository,
      productRepository: widget.productRepository,
      currentUserId: _currentUserId,
    );
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pagingController.loadInitial('');
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _pagingController.dispose();
    super.dispose();
  }

  String? get _currentUserId {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.id : null;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent - position.pixels <= 300) {
      _pagingController.loadMore();
    }
  }

  Future<void> _onSearchChanged(String query) async {
    await _pagingController.loadInitial(query);
  }

  void _cancelSearch() {
    _queryController.clear();
    FocusScope.of(context).unfocus();
    _pagingController.loadInitial('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Icon(
          Icons.search,
          size: 28,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        titleSpacing: 0,
        title: Align(
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: _queryController,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                ),
            decoration: InputDecoration(
              hintText: 'Поиск публикаций и товаров',
              hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 17,
                  ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: _onSearchChanged,
            onChanged: (value) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                if (!mounted) return;
                _onSearchChanged(value);
              });
            },
          ),
        ),
        actions: [
          if (_queryController.text.trim().isNotEmpty)
            TextButton(
              onPressed: _cancelSearch,
              child: const Text('Отмена'),
            ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _pagingController,
        builder: (context, _) {
          if (_pagingController.items.isEmpty && _pagingController.isLoading) {
            return const _InitialLoading();
          }

          if (_pagingController.items.isEmpty) {
            return Center(
              child: Text(
                _queryController.text.trim().isEmpty
                    ? 'Публикаций и товаров пока нет'
                    : 'Ничего не найдено по запросу "${_queryController.text.trim()}"',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            );
          }

          final items = _pagingController.items;
          final showBottomLoader =
              _pagingController.isLoading && _pagingController.hasMore;

          return ListView.builder(
            controller: _scrollController,
            itemCount: items.length + (showBottomLoader ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= items.length) return const _BottomSkeletonLoader();
              final item = items[index];
              if (item is SearchPostResultItem) {
                return _PostSearchTile(post: item.post);
              }
              if (item is SearchProductResultItem) {
                return _ProductSearchTile(product: item.product);
              }
              return const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }
}

class _InitialLoading extends StatelessWidget {
  const _InitialLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _PostSearchTile extends StatelessWidget {
  const _PostSearchTile({required this.post});

  final PostEntity post;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.push('/post/${post.id}', extra: post),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  CachedAvatar(
                    imageUrl: post.userAvatarUrl,
                    radius: 18,
                    fallbackText: post.userName,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      post.userName ?? 'Пользователь',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    _formatDate(post.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (post.videoUrl != null && post.videoUrl!.isNotEmpty)
              Container(
                height: 180,
                width: double.infinity,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.play_circle_fill_rounded, size: 56),
              )
            else if (post.imageUrl.isNotEmpty)
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CachedProductImage(imageUrl: post.imageUrl),
              ),
            if (post.caption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Text(
                  post.caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }
}

class _ProductSearchTile extends StatelessWidget {
  const _ProductSearchTile({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}', extra: product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Row(
                children: [
                  CachedAvatar(
                    imageUrl: product.sellerAvatarUrl,
                    radius: 18,
                    fallbackText: product.sellerName,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      product.sellerName ?? 'Продавец',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (product.createdAt != null)
                    Text(
                      _formatDate(product.createdAt!),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (product.imageUrl.isNotEmpty)
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CachedProductImage(imageUrl: product.imageUrl),
              )
            else
              Container(
                height: 180,
                width: double.infinity,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.shopping_bag_outlined, size: 48),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    product.priceFormatted,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w800,
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

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$day.$month.${value.year}';
  }
}

class _BottomSkeletonLoader extends StatelessWidget {
  const _BottomSkeletonLoader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.grey.withValues(alpha: 0.22),
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: Theme.of(context).colorScheme.primary,
                backgroundColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
