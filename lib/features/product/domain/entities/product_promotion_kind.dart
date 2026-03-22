/// Тип платной услуги для объявления (соответствует `kind` в `product_promotion_orders`).
enum ProductPromotionKind {
  /// «В топ» — поднимает видимость (флаг + срок в БД).
  top,

  /// «Срочно».
  urgent,

  /// Выделение цветом / рамкой в ленте.
  highlight,

  /// Доступ к статистике просмотров у продавца.
  stats,
}

extension ProductPromotionKindApi on ProductPromotionKind {
  /// Значение для Edge Function / Stripe metadata.
  String get apiValue {
    switch (this) {
      case ProductPromotionKind.top:
        return 'top';
      case ProductPromotionKind.urgent:
        return 'urgent';
      case ProductPromotionKind.highlight:
        return 'highlight';
      case ProductPromotionKind.stats:
        return 'stats';
    }
  }
}
