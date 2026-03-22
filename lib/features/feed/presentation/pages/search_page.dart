import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/data/kazakhstan_regions.dart';
import '../../../../core/models/search_filters.dart';
import '../../../../core/models/search_view_mode.dart';
import '../../../../core/storage/search_preferences_storage.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../product/domain/entities/category_entity.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../product/domain/repositories/categories_repository.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../controllers/search_paging_controller.dart';
import '../widgets/kazakhstan_location_sheet.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key, required this.productRepository});

  final ProductRepository productRepository;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _queryController = TextEditingController();
  final _scrollController = ScrollController();
  late final SearchPagingController _pagingController;
  SearchPreferencesStorage? _searchStorage;
  List<CategoryEntity> _categories = const [];
  List<String> _history = const [];
  List<SavedSearchFilter> _savedFilters = const [];
  final List<String> _popularQueries = const [
    'iPhone',
    'Квартира',
    'Ноутбук',
    'Диван',
    'Велосипед',
  ];
  Timer? _debounce;

  /// Локально сохраняется (как вид отображения в OLX).
  SearchViewMode _viewMode = SearchViewMode.list;

  @override
  void initState() {
    super.initState();
    _pagingController = SearchPagingController(
      productRepository: widget.productRepository,
      currentUserId: _currentUserId,
    );
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pagingController.loadInitial('');
      _bootstrapSearchUx();
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
    if (query.trim().isNotEmpty) {
      await _searchStorage?.addHistory(query.trim());
      _reloadLocalSearchPrefs();
    }
  }

  void _cancelSearch() {
    _queryController.clear();
    FocusScope.of(context).unfocus();
    _pagingController.loadInitial('');
    setState(() {});
  }

  Future<void> _bootstrapSearchUx() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final storage = SearchPreferencesStorage(prefs);
    List<CategoryEntity> categories = const [];
    try {
      categories = await context
          .read<CategoriesRepository>()
          .getMainCategories();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _searchStorage = storage;
      _categories = categories;
      _viewMode = storage.getSearchViewMode();
    });
    _reloadLocalSearchPrefs();
  }

  Future<void> _persistViewMode(SearchViewMode mode) async {
    setState(() => _viewMode = mode);
    await _searchStorage?.setSearchViewMode(mode);
  }

  Future<void> _showCategoryPicker() async {
    final picked = await showModalBottomSheet<CategoryEntity?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.all_inclusive_rounded),
              title: const Text('Все категории'),
              onTap: () => Navigator.pop(ctx, null),
            ),
            const Divider(height: 1),
            ..._categories.map(
              (c) => ListTile(
                title: Text(c.name),
                onTap: () => Navigator.pop(ctx, c),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    final f = _pagingController.filters;
    final next = picked == null
        ? f.copyWith(clearCategory: true)
        : f.copyWith(
            categoryId: picked.id,
            categoryName: picked.name,
          );
    await _pagingController.loadInitial(_queryController.text, filters: next);
    setState(() {});
  }

  Future<void> _showLocationDialog() async {
    final outcome = await showModalBottomSheet<KazakhstanLocationOutcome?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const KazakhstanLocationSheet(),
    );
    if (!mounted || outcome == null) return;
    final next = mergeLocationOutcome(_pagingController.filters, outcome);
    await _pagingController.loadInitial(_queryController.text, filters: next);
    setState(() {});
  }

  void _reloadLocalSearchPrefs() {
    final storage = _searchStorage;
    if (storage == null || !mounted) return;
    setState(() {
      _history = storage.getHistory();
      _savedFilters = storage.getSavedFilters();
    });
  }

  Future<void> _openFiltersSheet() async {
    final applied = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FiltersSheet(
        initial: _pagingController.filters,
        categories: _categories,
        shownCount: _pagingController.items.length,
      ),
    );
    if (applied == null) return;
    await _pagingController.loadInitial(
      _queryController.text,
      filters: applied,
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _saveCurrentFilter() async {
    final storage = _searchStorage;
    if (storage == null) return;
    final query = _queryController.text.trim();
    final filters = _pagingController.filters;
    if (query.isEmpty && !filters.hasActiveFilters) return;
    final label = query.isNotEmpty
        ? query
        : 'Фильтр ${DateTime.now().day}.${DateTime.now().month}';
    await storage.saveFilter(
      SavedSearchFilter(title: label, query: query, filters: filters),
    );
    _reloadLocalSearchPrefs();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Фильтр сохранен')));
  }

  Future<void> _applySavedFilter(SavedSearchFilter item) async {
    _queryController.text = item.query;
    await _pagingController.loadInitial(item.query, filters: item.filters);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _removeSavedFilter(String title) async {
    await _searchStorage?.removeSavedFilter(title);
    _reloadLocalSearchPrefs();
  }

  List<String> _autoSuggestions() {
    final q = _queryController.text.trim().toLowerCase();
    final source = <String>{
      ..._history,
      ..._popularQueries,
      ..._categories.map((e) => e.name),
    };
    if (q.isEmpty) {
      return source.take(8).toList(growable: false);
    }
    return source
        .where((s) => s.toLowerCase().contains(q))
        .take(8)
        .toList(growable: false);
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
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontSize: 17),
            decoration: InputDecoration(
              hintText: 'Поиск товаров',
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
          IconButton(
            tooltip: 'Фильтры',
            onPressed: _openFiltersSheet,
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Сохранить фильтр',
            onPressed: _saveCurrentFilter,
            icon: const Icon(Icons.bookmark_add_outlined),
          ),
          if (_queryController.text.trim().isNotEmpty)
            TextButton(onPressed: _cancelSearch, child: const Text('Отмена')),
        ],
      ),
      body: AnimatedBuilder(
        animation: _pagingController,
        builder: (context, _) {
          final filters = _pagingController.filters;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OlxSearchFilterBar(
                viewMode: _viewMode,
                filters: filters,
                onOpenFilters: _openFiltersSheet,
                onSortChanged: (sort) async {
                  final next = filters.copyWith(sort: sort);
                  await _pagingController.loadInitial(
                    _queryController.text,
                    filters: next,
                  );
                  if (mounted) setState(() {});
                },
                onCategoryTap: _showCategoryPicker,
                onLocationTap: _showLocationDialog,
                onViewModeChanged: _persistViewMode,
              ),
              Expanded(
                child: _buildSearchResultsPane(
                  suggestions: _autoSuggestions(),
                  filters: filters,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchResultsPane({
    required List<String> suggestions,
    required SearchFilters filters,
  }) {
    if (_pagingController.items.isEmpty && _pagingController.isLoading) {
      return const _InitialLoading();
    }

    if (_pagingController.items.isEmpty) {
      return _SearchEmptyState(
        query: _queryController.text.trim(),
        hasFilters: filters.hasActiveFilters,
        categories: _categories,
        onResetFilters: () => _pagingController.loadInitial(
          _queryController.text,
          filters: const SearchFilters(),
        ),
      );
    }

    final items = _pagingController.items;
    final showBottomLoader =
        _pagingController.isLoading && _pagingController.hasMore;

    return Column(
      children: [
        _QuickFilterRow(
          filters: filters,
          categories: _categories,
          onFilterTap: _openFiltersSheet,
          onClearOne: (type) async {
            SearchFilters updated = filters;
            switch (type) {
              case _QuickFilterType.category:
                updated = filters.copyWith(clearCategory: true);
                break;
              case _QuickFilterType.price:
                updated = filters.copyWith(
                  clearMinPrice: true,
                  clearMaxPrice: true,
                );
                break;
              case _QuickFilterType.city:
                updated = filters.copyWith(
                  clearCity: true,
                  clearKzLocation: true,
                  clearNearby: true,
                );
                break;
              case _QuickFilterType.nearby:
                updated = filters.copyWith(clearNearby: true);
                break;
              case _QuickFilterType.condition:
                updated = filters.copyWith(
                  condition: ProductCondition.any,
                );
                break;
              case _QuickFilterType.sort:
                updated = filters.copyWith(sort: SearchSort.newest);
                break;
            }
            await _pagingController.loadInitial(
              _queryController.text,
              filters: updated,
            );
            if (mounted) setState(() {});
          },
        ),
        if (_queryController.text.trim().isNotEmpty && suggestions.isNotEmpty)
          _SuggestionsBar(
            suggestions: suggestions,
            onTap: (value) {
              _queryController.text = value;
              _onSearchChanged(value);
              setState(() {});
            },
          ),
        if (_savedFilters.isNotEmpty)
          _SavedFiltersBar(
            items: _savedFilters,
            onTap: _applySavedFilter,
            onRemove: _removeSavedFilter,
          ),
        Expanded(
          child: _buildResultsScrollView(
            items: items,
            filters: filters,
            showBottomLoader: showBottomLoader,
          ),
        ),
      ],
    );
  }

  Widget _buildResultsScrollView({
    required List<SearchResultItem> items,
    required SearchFilters filters,
    required bool showBottomLoader,
  }) {
    switch (_viewMode) {
      case SearchViewMode.list:
        return ListView.builder(
          controller: _scrollController,
          itemCount: items.length + (showBottomLoader ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const _BottomSkeletonLoader();
            }
            final item = items[index];
            if (item is SearchProductResultItem) {
              return _ProductSearchListCompact(
                product: item.product,
                centerLatitude: filters.centerLatitude,
                centerLongitude: filters.centerLongitude,
              );
            }
            return const SizedBox.shrink();
          },
        );
      case SearchViewMode.gallery:
        return ListView.builder(
          controller: _scrollController,
          itemCount: items.length + (showBottomLoader ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final item = items[index];
            if (item is SearchProductResultItem) {
              return _ProductSearchGalleryCard(
                product: item.product,
                centerLatitude: filters.centerLatitude,
                centerLongitude: filters.centerLongitude,
              );
            }
            return const SizedBox.shrink();
          },
        );
      case SearchViewMode.tile:
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.68,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: items.length + (showBottomLoader ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= items.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            final item = items[index];
            if (item is SearchProductResultItem) {
              return _ProductSearchGridTile(
                product: item.product,
                centerLatitude: filters.centerLatitude,
                centerLongitude: filters.centerLongitude,
              );
            }
            return const SizedBox.shrink();
          },
        );
    }
  }
}

String _searchSortButtonLabel(SearchSort s) => switch (s) {
      SearchSort.newest => 'По дате',
      SearchSort.priceAsc => 'Дешевле',
      SearchSort.priceDesc => 'Дороже',
    };

String? _searchDistanceKmLabel(
  ProductEntity product,
  double? centerLatitude,
  double? centerLongitude,
) {
  final centerLat = centerLatitude;
  final centerLng = centerLongitude;
  final productLat = product.latitude;
  final productLng = product.longitude;
  if (centerLat == null ||
      centerLng == null ||
      productLat == null ||
      productLng == null) {
    return null;
  }
  const earthRadiusKm = 6371.0;
  final dLat = _degToRad(productLat - centerLat);
  final dLon = _degToRad(productLng - centerLng);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_degToRad(centerLat)) *
          math.cos(_degToRad(productLat)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  final distanceKm = earthRadiusKm * c;
  if (distanceKm < 1) {
    return '${(distanceKm * 1000).round()} м';
  }
  return '${distanceKm.toStringAsFixed(1)} км';
}

double _degToRad(double degrees) => degrees * math.pi / 180;

/// Панель как в OLX: фильтры, сортировка, категория, место, вид списка.
class _OlxSearchFilterBar extends StatelessWidget {
  const _OlxSearchFilterBar({
    required this.viewMode,
    required this.filters,
    required this.onOpenFilters,
    required this.onSortChanged,
    required this.onCategoryTap,
    required this.onLocationTap,
    required this.onViewModeChanged,
  });

  final SearchViewMode viewMode;
  final SearchFilters filters;
  final VoidCallback onOpenFilters;
  final ValueChanged<SearchSort> onSortChanged;
  final VoidCallback onCategoryTap;
  final VoidCallback onLocationTap;
  final ValueChanged<SearchViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFilters = filters.hasActiveFilters;
    final categoryLabel = filters.categoryName?.trim().isNotEmpty == true
        ? filters.categoryName!
        : 'Категория';
    final locationLabel = KazakhstanRegions.toolbarLabel(
      kzRegionId: filters.kzRegionId,
      kzLocalityName: filters.kzLocalityName,
      legacyCity: filters.city,
      radiusKm: filters.radiusKm,
      centerLatitude: filters.centerLatitude,
    );

    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: hasFilters,
                smallSize: 7,
                child: FilledButton.tonalIcon(
                  onPressed: onOpenFilters,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  label: const Text('Фильтры'),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<SearchSort>(
                tooltip: 'Сортировка',
                onSelected: onSortChanged,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: SearchSort.newest,
                    child: Text('Сначала новые'),
                  ),
                  const PopupMenuItem(
                    value: SearchSort.priceAsc,
                    child: Text('Сначала дешевле'),
                  ),
                  const PopupMenuItem(
                    value: SearchSort.priceDesc,
                    child: Text('Сначала дороже'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort_rounded, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 100),
                        child: Text(
                          _searchSortButtonLabel(filters.sort),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 132),
                child: OutlinedButton(
                  onPressed: onCategoryTap,
                  child: Text(
                    categoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: OutlinedButton.icon(
                  onPressed: onLocationTap,
                  icon: const Icon(Icons.place_outlined, size: 18),
                  label: Text(
                    locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<SearchViewMode>(
                segments: const [
                  ButtonSegment<SearchViewMode>(
                    value: SearchViewMode.list,
                    icon: Icon(Icons.view_list_rounded),
                    tooltip: 'Список',
                  ),
                  ButtonSegment<SearchViewMode>(
                    value: SearchViewMode.gallery,
                    icon: Icon(Icons.photo_library_outlined),
                    tooltip: 'Галерея',
                  ),
                  ButtonSegment<SearchViewMode>(
                    value: SearchViewMode.tile,
                    icon: Icon(Icons.grid_view_rounded),
                    tooltip: 'Плитка',
                  ),
                ],
                selected: {viewMode},
                onSelectionChanged: (next) {
                  if (next.isNotEmpty) onViewModeChanged(next.first);
                },
                showSelectedIcon: false,
                emptySelectionAllowed: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSearchListCompact extends StatelessWidget {
  const _ProductSearchListCompact({
    required this.product,
    this.centerLatitude,
    this.centerLongitude,
  });

  final ProductEntity product;
  final double? centerLatitude;
  final double? centerLongitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = _searchDistanceKmLabel(
      product,
      centerLatitude,
      centerLongitude,
    );
    final city = product.city?.trim().isNotEmpty == true
        ? product.city!
        : 'Город не указан';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}', extra: product),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: product.imageUrl.isNotEmpty
                      ? CachedProductImage(
                          imageUrl: product.imageUrl,
                          fit: BoxFit.cover,
                        )
                      : ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Center(
                            child: Icon(Icons.shopping_bag_outlined, size: 40),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.priceFormatted,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      dist != null ? '$city  •  $dist' : city,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

class _ProductSearchGalleryCard extends StatelessWidget {
  const _ProductSearchGalleryCard({
    required this.product,
    this.centerLatitude,
    this.centerLongitude,
  });

  final ProductEntity product;
  final double? centerLatitude;
  final double? centerLongitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTop = product.isTop;
    final isUrgent = product.isUrgent;
    final dist = _searchDistanceKmLabel(
      product,
      centerLatitude,
      centerLongitude,
    );
    final city = product.city?.trim().isNotEmpty == true
        ? product.city!
        : 'Город не указан';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}', extra: product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 260,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: product.imageUrl.isNotEmpty
                        ? CachedProductImage(
                            imageUrl: product.imageUrl,
                            fit: BoxFit.cover,
                          )
                        : ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Center(
                              child: Icon(
                                Icons.shopping_bag_outlined,
                                size: 64,
                              ),
                            ),
                          ),
                  ),
                  if (isTop || isUrgent)
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Wrap(
                        spacing: 6,
                        children: [
                          if (isTop) const _Badge(label: 'ТОП'),
                          if (isUrgent)
                            const _Badge(
                              label: 'СРОЧНО',
                              color: Color(0xFFE53935),
                            ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            product.priceFormatted,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Text(
                dist != null ? '$city  •  $dist' : city,
                style: theme.textTheme.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductSearchGridTile extends StatelessWidget {
  const _ProductSearchGridTile({
    required this.product,
    this.centerLatitude,
    this.centerLongitude,
  });

  final ProductEntity product;
  final double? centerLatitude;
  final double? centerLongitude;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dist = _searchDistanceKmLabel(
      product,
      centerLatitude,
      centerLongitude,
    );
    final city = product.city?.trim().isNotEmpty == true
        ? product.city!
        : '';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => context.push('/product/${product.id}', extra: product),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: product.imageUrl.isNotEmpty
                  ? CachedProductImage(
                      imageUrl: product.imageUrl,
                      fit: BoxFit.cover,
                    )
                  : ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.shopping_bag_outlined, size: 48),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.priceFormatted,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                  if (city.isNotEmpty || dist != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (city.isNotEmpty) city,
                        ?dist,
                      ].join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
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

class _InitialLoading extends StatelessWidget {
  const _InitialLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.color = const Color(0xFF1565C0)});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

enum _QuickFilterType { category, price, city, nearby, condition, sort }

class _QuickFilterRow extends StatelessWidget {
  const _QuickFilterRow({
    required this.filters,
    required this.categories,
    required this.onFilterTap,
    required this.onClearOne,
  });

  final SearchFilters filters;
  final List<CategoryEntity> categories;
  final VoidCallback onFilterTap;
  final Future<void> Function(_QuickFilterType type) onClearOne;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _quickChip(
        context,
        label: filters.categoryName ?? 'Категория',
        active: filters.categoryId != null,
        onTap: onFilterTap,
        onDelete: filters.categoryId != null
            ? () => onClearOne(_QuickFilterType.category)
            : null,
      ),
      _quickChip(
        context,
        label: filters.minPrice != null || filters.maxPrice != null
            ? '${filters.minPrice?.toStringAsFixed(0) ?? '0'} - ${filters.maxPrice?.toStringAsFixed(0) ?? '...'}'
            : 'Цена',
        active: filters.minPrice != null || filters.maxPrice != null,
        onTap: onFilterTap,
        onDelete: filters.minPrice != null || filters.maxPrice != null
            ? () => onClearOne(_QuickFilterType.price)
            : null,
      ),
      _quickChip(
        context,
        label: KazakhstanRegions.toolbarLabel(
          kzRegionId: filters.kzRegionId,
          kzLocalityName: filters.kzLocalityName,
          legacyCity: filters.city,
          radiusKm: filters.radiusKm,
          centerLatitude: filters.centerLatitude,
        ),
        active: (filters.city?.trim().isNotEmpty ?? false) ||
            (filters.kzRegionId != null &&
                filters.kzRegionId!.trim().isNotEmpty) ||
            (filters.radiusKm != null && filters.centerLatitude != null),
        onTap: onFilterTap,
        onDelete: ((filters.city?.trim().isNotEmpty ?? false) ||
                (filters.kzRegionId != null &&
                    filters.kzRegionId!.trim().isNotEmpty) ||
                (filters.radiusKm != null && filters.centerLatitude != null))
            ? () => onClearOne(_QuickFilterType.city)
            : null,
      ),
      _quickChip(
        context,
        label: filters.radiusKm != null
            ? 'Рядом: ${filters.radiusKm!.toStringAsFixed(0)} км'
            : 'Рядом',
        active: filters.radiusKm != null,
        onTap: onFilterTap,
        onDelete: filters.radiusKm != null
            ? () => onClearOne(_QuickFilterType.nearby)
            : null,
      ),
      _quickChip(
        context,
        label: switch (filters.condition) {
          ProductCondition.any => 'Состояние',
          ProductCondition.newOnly => 'Новый',
          ProductCondition.used => 'Б/у',
        },
        active: filters.condition != ProductCondition.any,
        onTap: onFilterTap,
        onDelete: filters.condition != ProductCondition.any
            ? () => onClearOne(_QuickFilterType.condition)
            : null,
      ),
      _quickChip(
        context,
        label: switch (filters.sort) {
          SearchSort.newest => 'Новые',
          SearchSort.priceAsc => 'Дешевле',
          SearchSort.priceDesc => 'Дороже',
        },
        active: filters.sort != SearchSort.newest,
        onTap: onFilterTap,
        onDelete: filters.sort != SearchSort.newest
            ? () => onClearOne(_QuickFilterType.sort)
            : null,
      ),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: chips,
      ),
    );
  }

  Widget _quickChip(
    BuildContext context, {
    required String label,
    required bool active,
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: FilterChip(
        selected: active,
        label: Text(label),
        onSelected: (_) => onTap(),
        deleteIcon: onDelete != null ? const Icon(Icons.close, size: 16) : null,
        onDeleted: onDelete,
      ),
    );
  }
}

class _SuggestionsBar extends StatelessWidget {
  const _SuggestionsBar({required this.suggestions, required this.onTap});
  final List<String> suggestions;
  final ValueChanged<String> onTap;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final text = suggestions[index];
          return ActionChip(label: Text(text), onPressed: () => onTap(text));
        },
      ),
    );
  }
}

class _SavedFiltersBar extends StatelessWidget {
  const _SavedFiltersBar({
    required this.items,
    required this.onTap,
    required this.onRemove,
  });
  final List<SavedSearchFilter> items;
  final ValueChanged<SavedSearchFilter> onTap;
  final ValueChanged<String> onRemove;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InputChip(
              label: Text(item.title),
              onPressed: () => onTap(item),
              onDeleted: () => onRemove(item.title),
            ),
          );
        },
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState({
    required this.query,
    required this.hasFilters,
    required this.categories,
    required this.onResetFilters,
  });
  final String query;
  final bool hasFilters;
  final List<CategoryEntity> categories;
  final VoidCallback onResetFilters;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 42),
            const SizedBox(height: 10),
            Text(
              query.isEmpty
                  ? 'Товаров пока нет'
                  : 'Ничего не найдено по запросу "$query"',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (hasFilters)
              TextButton(
                onPressed: onResetFilters,
                child: const Text('Сбросить фильтры'),
              ),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: categories
                    .take(6)
                    .map((c) => Chip(label: Text(c.name)))
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({
    required this.initial,
    required this.categories,
    required this.shownCount,
  });
  final SearchFilters initial;
  final List<CategoryEntity> categories;
  final int shownCount;
  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late SearchFilters _filters;
  late final TextEditingController _minCtrl;
  late final TextEditingController _maxCtrl;
  late final TextEditingController _cityCtrl;
  bool _nearbyEnabled = false;
  bool _resolvingLocation = false;
  static const List<double> _radiusOptions = [1, 3, 5, 10, 20, 50];
  late double _radiusKm;
  double? _centerLat;
  double? _centerLng;

  @override
  void initState() {
    super.initState();
    var initial = widget.initial;
    final cid = initial.categoryId;
    // Иначе DropdownButtonFormField падает: «нет ровно одного элемента с таким value».
    if (widget.categories.isEmpty) {
      if (cid != null && cid.isNotEmpty) {
        initial = initial.copyWith(clearCategory: true);
      }
    } else if (cid != null &&
        cid.isNotEmpty &&
        !widget.categories.any((c) => c.id == cid)) {
      initial = initial.copyWith(clearCategory: true);
    }
    _filters = initial;
    _minCtrl = TextEditingController(
      text: widget.initial.minPrice?.toStringAsFixed(0) ?? '',
    );
    _maxCtrl = TextEditingController(
      text: widget.initial.maxPrice?.toStringAsFixed(0) ?? '',
    );
    _cityCtrl = TextEditingController(text: widget.initial.city ?? '');
    _nearbyEnabled = widget.initial.radiusKm != null;
    _radiusKm = widget.initial.radiusKm ?? 5;
    if (!_radiusOptions.contains(_radiusKm)) {
      _radiusKm = 5;
    }
    _centerLat = widget.initial.centerLatitude;
    _centerLng = widget.initial.centerLongitude;
  }

  /// Значение из фильтра должно совпадать с одним из items, иначе Dropdown падает.
  String? get _safeCategoryDropdownValue {
    final id = _filters.categoryId;
    if (id == null || id.isEmpty) return null;
    return widget.categories.any((c) => c.id == id) ? id : null;
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Фильтры', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              key: ValueKey<String?>(_safeCategoryDropdownValue),
              initialValue: _safeCategoryDropdownValue,
              decoration: const InputDecoration(labelText: 'Категория'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Все категории'),
                ),
                ...widget.categories.map(
                  (c) => DropdownMenuItem<String?>(
                    value: c.id,
                    child: Text(c.name),
                  ),
                ),
              ],
              onChanged: (value) {
                CategoryEntity? selected;
                for (final c in widget.categories) {
                  if (c.id == value) {
                    selected = c;
                    break;
                  }
                }
                setState(() {
                  _filters = _filters.copyWith(
                    categoryId: value,
                    categoryName: selected?.name,
                    clearCategory: value == null,
                  );
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Цена от'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Цена до'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _cityCtrl,
              decoration: const InputDecoration(labelText: 'Город'),
            ),
            const SizedBox(height: 10),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Рядом со мной'),
              subtitle: Text(
                _centerLat == null || _centerLng == null
                    ? 'Локация не выбрана'
                    : 'Точка выбрана',
              ),
              value: _nearbyEnabled,
              onChanged: (value) {
                setState(() => _nearbyEnabled = value);
              },
            ),
            if (_nearbyEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      key: ValueKey<double>(_radiusKm),
                      initialValue: _radiusKm,
                      decoration: const InputDecoration(labelText: 'Радиус'),
                      items: _radiusOptions
                          .map(
                            (e) => DropdownMenuItem<double>(
                              value: e,
                              child: Text('${e.toStringAsFixed(0)} км'),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _radiusKm = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _resolvingLocation ? null : _pickCurrentLocation,
                    icon: _resolvingLocation
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: const Text('Моя геопозиция'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            DropdownButtonFormField<ProductCondition>(
              initialValue: _filters.condition,
              decoration: const InputDecoration(labelText: 'Состояние'),
              items: const [
                DropdownMenuItem(
                  value: ProductCondition.any,
                  child: Text('Любое'),
                ),
                DropdownMenuItem(
                  value: ProductCondition.newOnly,
                  child: Text('Новый'),
                ),
                DropdownMenuItem(
                  value: ProductCondition.used,
                  child: Text('Б/у'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _filters = _filters.copyWith(condition: value));
              },
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<SearchSort>(
              initialValue: _filters.sort,
              decoration: const InputDecoration(labelText: 'Сортировка'),
              items: const [
                DropdownMenuItem(
                  value: SearchSort.newest,
                  child: Text('Новые'),
                ),
                DropdownMenuItem(
                  value: SearchSort.priceAsc,
                  child: Text('Дешевле'),
                ),
                DropdownMenuItem(
                  value: SearchSort.priceDesc,
                  child: Text('Дороже'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _filters = _filters.copyWith(sort: value));
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop(const SearchFilters());
                    },
                    child: const Text('Сбросить'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      final min = double.tryParse(_minCtrl.text.trim());
                      final max = double.tryParse(_maxCtrl.text.trim());
                      final canApplyNearby =
                          _nearbyEnabled &&
                          _centerLat != null &&
                          _centerLng != null;
                      final out = _filters.copyWith(
                        minPrice: min,
                        maxPrice: max,
                        city: _cityCtrl.text.trim(),
                        radiusKm: canApplyNearby ? _radiusKm : null,
                        centerLatitude: canApplyNearby ? _centerLat : null,
                        centerLongitude: canApplyNearby ? _centerLng : null,
                        clearCity: _cityCtrl.text.trim().isEmpty,
                        clearKzLocation: _cityCtrl.text.trim().isNotEmpty,
                        clearMinPrice: _minCtrl.text.trim().isEmpty,
                        clearMaxPrice: _maxCtrl.text.trim().isEmpty,
                        clearNearby: !canApplyNearby,
                      );
                      Navigator.of(context).pop(out);
                    },
                    child: Text('Показать ${widget.shownCount}'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCurrentLocation() async {
    setState(() => _resolvingLocation = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Включите геолокацию на устройстве')),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к геолокации')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() {
        _centerLat = pos.latitude;
        _centerLng = pos.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Геопозиция выбрана для фильтра рядом')),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted) return;
      if (last != null) {
        setState(() {
          _centerLat = last.latitude;
          _centerLng = last.longitude;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Использована последняя геопозиция')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось определить геопозицию')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка получения геопозиции')),
      );
    } finally {
      if (mounted) setState(() => _resolvingLocation = false);
    }
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
