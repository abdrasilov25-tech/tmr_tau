import 'package:equatable/equatable.dart';

import '../entities/product_entity.dart';

/// Подсказка «дороже/дешевле похожих» по квартилям выборки цен.
enum InsightTone { favorable, neutral, caution }

class ProductPriceInsight extends Equatable {
  const ProductPriceInsight({
    required this.headline,
    this.detail,
    required this.tone,
  });

  final String headline;
  final String? detail;
  final InsightTone tone;

  /// Сравнение с товарами в текущей выдаче поиска (предпочтительно та же категория).
  static ProductPriceInsight? fromSearchPeers(
    ProductEntity subject,
    List<ProductEntity> listingProducts,
  ) {
    if (subject.isGiveaway || subject.price <= 0) return null;
    final cid = subject.categoryId?.trim();
    final Iterable<ProductEntity> pool = cid != null && cid.isNotEmpty
        ? listingProducts.where(
            (p) => (p.categoryId?.trim() ?? '') == cid,
          )
        : listingProducts;
    final prices = pool
        .where(
          (p) =>
              p.id != subject.id && !p.isGiveaway && p.price > 0,
        )
        .map((p) => p.price)
        .toList();
    return fromComparablePrices(subjectPrice: subject.price, peerPrices: prices);
  }

  /// Сравнение с произвольным набором цен (например, из БД по категории).
  static ProductPriceInsight? fromComparablePrices({
    required double subjectPrice,
    required List<double> peerPrices,
  }) {
    if (subjectPrice <= 0) return null;
    final sorted = peerPrices.where((p) => p > 0).toList()..sort();
    if (sorted.length < 5) return null;

    final n = sorted.length;
    double atFraction(double t) {
      if (n == 1) return sorted[0];
      final i = (t * (n - 1)).round().clamp(0, n - 1);
      return sorted[i];
    }

    final p25 = atFraction(0.25);
    final p50 = atFraction(0.5);
    final p75 = atFraction(0.75);

    if (subjectPrice <= p25 * 1.02) {
      return const ProductPriceInsight(
        headline: 'Выгодная цена',
        detail: 'Заметно дешевле большинства похожих',
        tone: InsightTone.favorable,
      );
    }
    if (subjectPrice < p50 * 0.97) {
      return const ProductPriceInsight(
        headline: 'Дешевле среднего',
        detail: 'Ниже типичной цены среди похожих',
        tone: InsightTone.favorable,
      );
    }
    if (subjectPrice >= p75 * 0.98) {
      return const ProductPriceInsight(
        headline: 'Выше рынка',
        detail: 'Дороже большинства похожих объявлений',
        tone: InsightTone.caution,
      );
    }
    if (subjectPrice > p50 * 1.03) {
      return const ProductPriceInsight(
        headline: 'Чуть дороже',
        detail: 'Выше средней по похожим товарам',
        tone: InsightTone.neutral,
      );
    }
    return const ProductPriceInsight(
      headline: 'Обычная цена',
      detail: 'В типичном диапазоне для похожих',
      tone: InsightTone.neutral,
    );
  }

  @override
  List<Object?> get props => [headline, detail, tone];
}
