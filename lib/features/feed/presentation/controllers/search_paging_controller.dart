import 'package:flutter/foundation.dart';

import '../../../../core/models/search_filters.dart';
import '../../../product/domain/entities/product_entity.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../../../settings/domain/load_all_blocked_user_ids.dart';
import '../../../settings/domain/repositories/settings_repository.dart';

sealed class SearchResultItem {
  DateTime get createdAt;
}

class SearchProductResultItem extends SearchResultItem {
  SearchProductResultItem(this.product);

  final ProductEntity product;

  @override
  DateTime get createdAt =>
      product.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class SearchPagingController extends ChangeNotifier {
  SearchPagingController({
    required ProductRepository productRepository,
    this.currentUserId,
    this.settingsRepository,
    this.pageSize = 20,
  }) : _productRepository = productRepository;

  final ProductRepository _productRepository;
  final String? currentUserId;
  final SettingsRepository? settingsRepository;
  final int pageSize;

  Set<String>? _cachedExcludeSellerIds;

  final List<ProductEntity> _products = [];
  final List<SearchResultItem> _items = [];
  List<SearchResultItem> get items => List.unmodifiable(_items);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasMoreProducts = true;
  bool get hasMoreProducts => _hasMoreProducts;

  bool get hasMore => _hasMoreProducts;

  int _productOffset = 0;

  String _query = '';
  String get query => _query;
  SearchFilters _filters = const SearchFilters();
  SearchFilters get filters => _filters;

  int _requestVersion = 0;

  /// Пустая выдача без запроса (смена аккаунта / сброс отложенной загрузки).
  void resetListing() {
    _requestVersion++;
    _query = '';
    _filters = const SearchFilters();
    _cachedExcludeSellerIds = null;
    _products.clear();
    _items.clear();
    _productOffset = 0;
    _hasMoreProducts = true;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadInitial(String query, {SearchFilters? filters}) async {
    _requestVersion++;
    final localVersion = _requestVersion;
    _query = query.trim();
    if (filters != null) {
      _filters = filters;
    }
    _cachedExcludeSellerIds = null;
    _products.clear();
    _items.clear();
    _productOffset = 0;
    _hasMoreProducts = true;
    _isLoading = true;
    notifyListeners();

    await _fetchPage(reset: true, requestVersion: localVersion);
  }

  Future<void> loadMore() async {
    if (_isLoading || !hasMore) return;
    await _fetchPage(reset: false, requestVersion: _requestVersion);
  }

  /// Убрать товар из текущей выдачи (после удаления объявления).
  void removeProductById(String productId) {
    _products.removeWhere((p) => p.id == productId);
    _items
      ..clear()
      ..addAll(_products.map(SearchProductResultItem.new))
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  Future<void> _fetchPage({
    required bool reset,
    required int requestVersion,
  }) async {
    if (_isLoading && !reset) return;
    _isLoading = true;
    notifyListeners();
    try {
      final shouldFetchProducts = reset || _hasMoreProducts;
      final exclude = await _resolveExcludeSellerIds();

      final fetchedProducts = shouldFetchProducts
          ? await _productRepository.searchProductsWithOffset(
              _query,
              limit: pageSize,
              offset: reset ? 0 : _productOffset,
              currentUserId: currentUserId,
              filters: _filters,
              excludeSellerIds: exclude,
            )
          : const <ProductEntity>[];

      if (requestVersion != _requestVersion) return;

      if (reset) {
        _products
          ..clear()
          ..addAll(fetchedProducts);
      } else {
        _products.addAll(fetchedProducts);
      }

      _productOffset = _productOffset + fetchedProducts.length;
      _hasMoreProducts = fetchedProducts.length == pageSize;

      _items
        ..clear()
        ..addAll(_products.map(SearchProductResultItem.new))
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } finally {
      if (requestVersion == _requestVersion) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<Set<String>> _resolveExcludeSellerIds() async {
    if (_cachedExcludeSellerIds != null) return _cachedExcludeSellerIds!;

    final uid = currentUserId;
    final settings = settingsRepository;
    if (uid == null || uid.isEmpty || settings == null) {
      _cachedExcludeSellerIds = {};
      return _cachedExcludeSellerIds!;
    }
    try {
      _cachedExcludeSellerIds = await loadAllBlockedUserIds(
        repository: settings,
        blockerId: uid,
      );
    } catch (_) {
      _cachedExcludeSellerIds = {};
    }
    return _cachedExcludeSellerIds!;
  }
}
