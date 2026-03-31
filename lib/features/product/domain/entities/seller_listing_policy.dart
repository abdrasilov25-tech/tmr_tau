enum SellerPlanType { free, standard, pro }

class SellerListingPolicy {
  const SellerListingPolicy({
    required this.plan,
    required this.maxActiveProducts,
    required this.activeProducts,
  });

  final SellerPlanType plan;
  final int? maxActiveProducts;
  final int activeProducts;

  bool get isUnlimited => maxActiveProducts == null;
  int get remainingSlots {
    if (maxActiveProducts == null) return 999999;
    final left = maxActiveProducts! - activeProducts;
    return left < 0 ? 0 : left;
  }

  bool get canCreateProduct => isUnlimited || remainingSlots > 0;

  String get planLabel {
    switch (plan) {
      case SellerPlanType.free:
        return 'Базовый';
      case SellerPlanType.standard:
        return 'Стандарт';
      case SellerPlanType.pro:
        return 'Про';
    }
  }
}
