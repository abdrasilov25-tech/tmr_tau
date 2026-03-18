import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/themed_content_surface.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../../core/widgets/verified_badge.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../../../profile/domain/entities/seller_profile_entity.dart';
import '../../../profile/domain/repositories/profile_repository.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    required this.productRepository,
    required this.profileRepository,
  });

  final ProductRepository productRepository;
  final ProfileRepository profileRepository;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ProductEntity> _productResults = [];
  List<SellerProfileEntity> _userResults = [];
  List<ProductEntity> _trending = [];
  List<SellerProfileEntity> _verifiedUsers = [];
  bool _loading = false;
  bool _trendingLoading = false;
  bool _verifiedLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadTrending();
        _loadVerifiedUsers();
      }
    });
  }

  Future<void> _loadVerifiedUsers() async {
    setState(() => _verifiedLoading = true);
    try {
      final list = await widget.profileRepository.getVerifiedUsers();
      if (mounted) setState(() => _verifiedUsers = list);
    } finally {
      if (mounted) setState(() => _verifiedLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  String? get _currentUserId {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.user.id : null;
  }

  Future<void> _loadTrending() async {
    setState(() => _trendingLoading = true);
    try {
      final list = await widget.productRepository.getTrendingProducts(
        limit: 30,
        currentUserId: _currentUserId,
      );
      if (mounted) setState(() => _trending = list);
    } finally {
      if (mounted) setState(() => _trendingLoading = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _productResults = [];
        _userResults = [];
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.productRepository.searchProducts(
          query,
          limit: 30,
          currentUserId: _currentUserId,
        ),
        widget.profileRepository.searchUsers(query, limit: 50),
      ]);
      if (mounted) {
        setState(() {
          _productResults = results[0] as List<ProductEntity>;
          _userResults = results[1] as List<SellerProfileEntity>;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() {
        _productResults = [];
        _userResults = [];
        _loading = false;
      });
    }
  }

  void _cancelSearch() {
    _controller.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _productResults = [];
      _userResults = [];
    });
  }

  bool get _hasSearchResults =>
      _productResults.isNotEmpty || _userResults.isNotEmpty;

  bool get _hasSearchQuery => _controller.text.trim().isNotEmpty;

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
            controller: _controller,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                ),
            decoration: InputDecoration(
              hintText: 'Поиск',
              hintStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 17,
                  ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              isDense: false,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: _search,
            onChanged: (value) {
              setState(() {});
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                if (!mounted) return;
                _search(value);
              });
            },
          ),
        ),
        actions: [
          if (_hasSearchQuery)
            TextButton(
              onPressed: _cancelSearch,
              child: const Text('Отмена'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _hasSearchResults
              ? _SearchResultsView(
                  products: _productResults,
                  users: _userResults,
                )
              : _controller.text.trim().isEmpty
                  ? _TrendingSection(
                      trending: _trending,
                      loading: _trendingLoading,
                      verifiedUsers: _verifiedUsers,
                      verifiedLoading: _verifiedLoading,
                    )
                  : _SimilarAndEmpty(
                      query: _controller.text.trim(),
                      trending: _trending,
                    ),
    );
  }
}

/// Когда по запросу ничего не найдено — показываем похожие товары.
class _SimilarAndEmpty extends StatelessWidget {
  const _SimilarAndEmpty({
    required this.query,
    required this.trending,
  });

  final String query;
  final List<ProductEntity> trending;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Center(
              child: Text(
                'По запросу «$query» ничего не найдено',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Похожие товары',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
        ),
        if (trending.isEmpty)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ProductGridTile(product: trending[index]),
                childCount: trending.length,
              ),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// Результаты поиска: пользователи сверху, товары сеткой 3 колонки.
class _SearchResultsView extends StatelessWidget {
  const _SearchResultsView({
    required this.products,
    required this.users,
  });

  final List<ProductEntity> products;
  final List<SellerProfileEntity> users;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (users.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Пользователи',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _UserTile(profile: users[index]),
              childCount: users.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
        if (products.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Товары',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final p = products[index];
                  return _ProductGridTile(product: p);
                },
                childCount: products.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ],
    );
  }
}

/// Строка пользователя в результатах поиска: круглая аватарка слева, имя справа (как в Instagram).
class _UserTile extends StatelessWidget {
  const _UserTile({required this.profile});

  final SellerProfileEntity profile;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/profile/${profile.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CachedAvatar(
              imageUrl: profile.avatarUrl,
              radius: 32,
              fallbackText: profile.name,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      profile.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (profile.isVerified) ...[
                    const SizedBox(width: 8),
                    const VerifiedBadge(size: 18),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Одна ячейка товара в сетке 3 колонки (квадрат, как в Instagram).
class _ProductGridTile extends StatelessWidget {
  const _ProductGridTile({required this.product});

  final ProductEntity product;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/product/${product.id}', extra: product),
      child: AspectRatio(
        aspectRatio: 1,
        child: CachedProductImage(imageUrl: product.imageUrl),
      ),
    );
  }
}

class _TrendingSection extends StatelessWidget {
  const _TrendingSection({
    required this.trending,
    required this.loading,
    required this.verifiedUsers,
    required this.verifiedLoading,
  });

  final List<ProductEntity> trending;
  final bool loading;
  final List<SellerProfileEntity> verifiedUsers;
  final bool verifiedLoading;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        if (verifiedLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          )
        else if (verifiedUsers.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text(
                'Официальная страница',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _OfficialPageCard(profile: verifiedUsers[index]),
              childCount: verifiedUsers.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
        ],
        if (loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (trending.isEmpty && verifiedUsers.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Text(
                'Введите запрос для поиска товаров и пользователей',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'В тренде',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ProductGridTile(product: trending[index]),
                childCount: trending.length,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ],
    );
  }
}

class _OfficialPageCard extends StatelessWidget {
  const _OfficialPageCard({required this.profile});

  final SellerProfileEntity profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.push('/profile/${profile.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CachedAvatar(
                imageUrl: profile.avatarUrl,
                radius: 28,
                fallbackText: profile.name,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        profile.name,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const VerifiedBadge(size: 18),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
