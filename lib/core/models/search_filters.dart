enum SearchSort { newest, priceAsc, priceDesc }

enum ProductCondition { any, newOnly, used }

class SearchFilters {
  const SearchFilters({
    this.categoryId,
    this.categoryName,
    this.minPrice,
    this.maxPrice,
    this.city,
    this.radiusKm,
    this.centerLatitude,
    this.centerLongitude,
    this.condition = ProductCondition.any,
    this.sort = SearchSort.newest,
  });

  final String? categoryId;
  final String? categoryName;
  final double? minPrice;
  final double? maxPrice;
  final String? city;
  final double? radiusKm;
  final double? centerLatitude;
  final double? centerLongitude;
  final ProductCondition condition;
  final SearchSort sort;

  bool get hasActiveFilters =>
      (categoryId != null && categoryId!.isNotEmpty) ||
      minPrice != null ||
      maxPrice != null ||
      (city != null && city!.trim().isNotEmpty) ||
      radiusKm != null ||
      condition != ProductCondition.any ||
      sort != SearchSort.newest;

  SearchFilters copyWith({
    String? categoryId,
    String? categoryName,
    double? minPrice,
    double? maxPrice,
    String? city,
    double? radiusKm,
    double? centerLatitude,
    double? centerLongitude,
    ProductCondition? condition,
    SearchSort? sort,
    bool clearCategory = false,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    bool clearCity = false,
    bool clearNearby = false,
  }) {
    return SearchFilters(
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      categoryName: clearCategory ? null : (categoryName ?? this.categoryName),
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      city: clearCity ? null : (city ?? this.city),
      radiusKm: clearNearby ? null : (radiusKm ?? this.radiusKm),
      centerLatitude: clearNearby ? null : (centerLatitude ?? this.centerLatitude),
      centerLongitude:
          clearNearby ? null : (centerLongitude ?? this.centerLongitude),
      condition: condition ?? this.condition,
      sort: sort ?? this.sort,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'categoryId': categoryId,
      'categoryName': categoryName,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
      'city': city,
      'radiusKm': radiusKm,
      'centerLatitude': centerLatitude,
      'centerLongitude': centerLongitude,
      'condition': condition.name,
      'sort': sort.name,
    };
  }

  factory SearchFilters.fromJson(Map<String, dynamic> json) {
    SearchSort parseSort(String? value) {
      return SearchSort.values.firstWhere(
        (e) => e.name == value,
        orElse: () => SearchSort.newest,
      );
    }

    ProductCondition parseCondition(String? value) {
      return ProductCondition.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ProductCondition.any,
      );
    }

    return SearchFilters(
      categoryId: json['categoryId'] as String?,
      categoryName: json['categoryName'] as String?,
      minPrice: (json['minPrice'] as num?)?.toDouble(),
      maxPrice: (json['maxPrice'] as num?)?.toDouble(),
      city: json['city'] as String?,
      radiusKm: (json['radiusKm'] as num?)?.toDouble(),
      centerLatitude: (json['centerLatitude'] as num?)?.toDouble(),
      centerLongitude: (json['centerLongitude'] as num?)?.toDouble(),
      condition: parseCondition(json['condition'] as String?),
      sort: parseSort(json['sort'] as String?),
    );
  }
}
