import 'package:flutter/foundation.dart';

import '../../../product/domain/entities/product_entity.dart';
import '../../../product/domain/repositories/product_repository.dart';

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
    this.pageSize = 10,
  }) : _productRepository = productRepository;

  final ProductRepository _productRepository;
  final String? currentUserId;
  final int pageSize;

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

  int _requestVersion = 0;

  Future<void> loadInitial(String query) async {
    _requestVersion++;
    final localVersion = _requestVersion;
    _query = query.trim();
    _products.clear();
    _items.clear();
    _productOffset = 0;
    _hasMoreProducts = true;
    notifyListeners();

    await _fetchPage(reset: true, requestVersion: localVersion);
  }

  Future<void> loadMore() async {
    if (_isLoading || !hasMore) return;
    await _fetchPage(reset: false, requestVersion: _requestVersion);
  }

  Future<void> _fetchPage({
    required bool reset,
    required int requestVersion,
  }) async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final shouldFetchProducts = reset || _hasMoreProducts;

      final fetchedProducts = shouldFetchProducts
          ? await _productRepository.searchProductsWithOffset(
              _query,
              limit: pageSize,
              offset: reset ? 0 : _productOffset,
              currentUserId: currentUserId,
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
}
