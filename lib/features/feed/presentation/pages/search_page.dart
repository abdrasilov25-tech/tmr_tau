import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
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
  List<ProductEntity> _results = [];
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
        limit: 10,
        currentUserId: _currentUserId,
      );
      if (mounted) setState(() => _trending = list);
    } finally {
      if (mounted) setState(() => _trendingLoading = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await widget.productRepository.searchProducts(
        query,
        limit: 20,
        currentUserId: _currentUserId,
      );
      if (mounted) setState(() => _results = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: TextField(
          controller: _controller,
          decoration: const InputDecoration(
            hintText: 'Товары и продавцы...',
            border: InputBorder.none,
          ),
          onSubmitted: _search,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isNotEmpty
              ? _ProductGrid(products: _results)
              : _controller.text.isEmpty
                  ? _TrendingSection(
                      trending: _trending,
                      loading: _trendingLoading,
                      verifiedUsers: _verifiedUsers,
                      verifiedLoading: _verifiedLoading,
                    )
                  : Center(
                      child: Text(
                        'Ничего не найдено',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (verifiedLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (verifiedUsers.isNotEmpty) ...[
          Text(
            'Официальная страница',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          ...verifiedUsers.map((u) => _OfficialPageCard(profile: u)),
          const SizedBox(height: 24),
        ],
        if (loading)
          const Center(child: CircularProgressIndicator())
        else if (trending.isEmpty && verifiedUsers.isEmpty)
          Center(
            child: Text(
              'Введите запрос для поиска',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          )
        else ...[
          Text(
            'В тренде',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          _ProductGrid(products: trending),
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
      margin: const EdgeInsets.only(bottom: 12),
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
              Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products});

  final List<ProductEntity> products;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () => context.push('/product/${p.id}', extra: p),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CachedProductImage(
                    imageUrl: p.imageUrl,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    p.priceFormatted,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
