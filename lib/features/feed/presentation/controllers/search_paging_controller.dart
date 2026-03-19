import 'package:flutter/foundation.dart';

import '../../../product/domain/entities/product_entity.dart';
import '../../../product/domain/repositories/product_repository.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';

sealed class SearchResultItem {
  DateTime get createdAt;
}

class SearchPostResultItem extends SearchResultItem {
  SearchPostResultItem(this.post);

  final PostEntity post;

  @override
  DateTime get createdAt => post.createdAt;
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
    required PostRepository postRepository,
    required ProductRepository productRepository,
    this.currentUserId,
    this.pageSize = 10,
  })  : _postRepository = postRepository,
        _productRepository = productRepository;

  final PostRepository _postRepository;
  final ProductRepository _productRepository;
  final String? currentUserId;
  final int pageSize;

  final List<PostEntity> _posts = [];
  final List<ProductEntity> _products = [];
  final List<SearchResultItem> _items = [];
  List<SearchResultItem> get items => List.unmodifiable(_items);

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _hasMorePosts = true;
  bool get hasMorePosts => _hasMorePosts;

  bool _hasMoreProducts = true;
  bool get hasMoreProducts => _hasMoreProducts;

  bool get hasMore => _hasMorePosts || _hasMoreProducts;

  DateTime? _lastCreatedAt;
  DateTime? get lastCreatedAt => _lastCreatedAt;

  int _productOffset = 0;

  String _query = '';
  String get query => _query;

  int _requestVersion = 0;

  Future<void> loadInitial(String query) async {
    _requestVersion++;
    final localVersion = _requestVersion;
    _query = query.trim();
    _posts.clear();
    _products.clear();
    _items.clear();
    _lastCreatedAt = null;
    _productOffset = 0;
    _hasMorePosts = true;
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
      final shouldFetchPosts = reset || _hasMorePosts;
      final shouldFetchProducts = reset || _hasMoreProducts;

      final fetchedPosts = shouldFetchPosts
          ? await _postRepository.searchPublicationsByCursor(
              query: _query,
              limit: pageSize,
              lastCreatedAt: reset ? null : _lastCreatedAt,
              currentUserId: currentUserId,
            )
          : const <PostEntity>[];

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
        _posts
          ..clear()
          ..addAll(fetchedPosts);
        _products
          ..clear()
          ..addAll(fetchedProducts);
      } else {
        _posts.addAll(fetchedPosts);
        _products.addAll(fetchedProducts);
      }

      _lastCreatedAt = _posts.isNotEmpty ? _posts.last.createdAt : null;
      _hasMorePosts = fetchedPosts.length == pageSize;
      _productOffset = _productOffset + fetchedProducts.length;
      _hasMoreProducts = fetchedProducts.length == pageSize;

      // Build unified list sorted by createdAt.
      _items
        ..clear()
        ..addAll(_posts.map(SearchPostResultItem.new))
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
