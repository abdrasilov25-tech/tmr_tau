import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/models/search_filters.dart';
import '../../../../core/storage/search_preferences_storage.dart';
import '../../../../core/widgets/cached_avatar.dart';
import '../../../../core/widgets/cached_product_image.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../product/domain/entities/category_entity.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../product/domain/repositories/categories_repository.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../controllers/search_paging_controller.dart';

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
    });
    _reloadLocalSearchPrefs();
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
          final suggestions = _autoSuggestions();
          final filters = _pagingController.filters;
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
                      updated = filters.copyWith(clearCity: true);
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
              if (_queryController.text.trim().isNotEmpty &&
                  suggestions.isNotEmpty)
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
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: items.length + (showBottomLoader ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= items.length) {
                      return const _BottomSkeletonLoader();
                    }
                    final item = items[index];
                    if (item is SearchProductResultItem) {
                      return _ProductSearchTile(
                        product: item.product,
                        centerLatitude: filters.centerLatitude,
                        centerLongitude: filters.centerLongitude,
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
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

class _ProductSearchTile extends StatelessWidget {
  const _ProductSearchTile({
    required this.product,
    this.centerLatitude,
    this.centerLongitude,
  });

  final ProductEntity product;
  final double? centerLatitude;
  final double? centerLongitude;

  @override
  Widget build(BuildContext context) {
    final isTop = product.isTop;
    final isUrgent = product.isUrgent;
    final distanceLabel = _buildDistanceLabel();
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
                height: 220,
                width: double.infinity,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CachedProductImage(imageUrl: product.imageUrl),
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
                  ],
                ),
              )
            else
              Container(
                height: 220,
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
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _buildMetaText(distanceLabel),
                    style: Theme.of(context).textTheme.bodySmall,
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

  String _buildMetaText(String? distanceLabel) {
    final city = product.city?.trim().isNotEmpty == true
        ? product.city!
        : 'Город не указан';
    final date = product.createdAt != null ? _formatDate(product.createdAt!) : '';
    if (distanceLabel != null && date.isNotEmpty) {
      return '$city  •  $distanceLabel  •  $date';
    }
    if (distanceLabel != null) return '$city  •  $distanceLabel';
    if (date.isNotEmpty) return '$city  •  $date';
    return city;
  }

  String? _buildDistanceLabel() {
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
    final distanceKm = _distanceKm(centerLat, centerLng, productLat, productLng);
    if (distanceKm < 1) {
      return '${(distanceKm * 1000).round()} м';
    }
    return '${distanceKm.toStringAsFixed(1)} км';
  }

  double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    const earthRadiusKm = 6371.0;
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a =
        _sinSquared(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) *
            math.cos(_degreesToRadians(lat2)) *
            _sinSquared(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) => degrees * math.pi / 180;

  double _sinSquared(double value) {
    final s = math.sin(value);
    return s * s;
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
        label: (filters.city?.trim().isNotEmpty ?? false)
            ? filters.city!
            : 'Город',
        active: filters.city?.trim().isNotEmpty ?? false,
        onTap: onFilterTap,
        onDelete: (filters.city?.trim().isNotEmpty ?? false)
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
    _filters = widget.initial;
    _minCtrl = TextEditingController(
      text: widget.initial.minPrice?.toStringAsFixed(0) ?? '',
    );
    _maxCtrl = TextEditingController(
      text: widget.initial.maxPrice?.toStringAsFixed(0) ?? '',
    );
    _cityCtrl = TextEditingController(text: widget.initial.city ?? '');
    _nearbyEnabled = widget.initial.radiusKm != null;
    _radiusKm = widget.initial.radiusKm ?? 5;
    _centerLat = widget.initial.centerLatitude;
    _centerLng = widget.initial.centerLongitude;
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
              initialValue: _filters.categoryId,
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
