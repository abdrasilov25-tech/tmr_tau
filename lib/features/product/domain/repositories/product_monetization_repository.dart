import '../entities/product_promotion_kind.dart';
import '../entities/promotion_checkout_session.dart';
import '../entities/promotion_order_status.dart';
import '../entities/promotion_stats.dart';

/// Оплата продвижения объявления (Stripe / Halyk / Caspipay через Supabase Edge Functions).
///
/// Реализация не вызывает платёжные API напрямую из Flutter — только `functions.invoke`.
abstract class ProductMonetizationRepository {
  /// Cloud Code: активация продвижения (создание заказа + ссылка оплаты).
  Future<PromotionCheckoutSession> activatePromotion({
    required String userId,
    required String productId,
    required ProductPromotionKind promoType,
  });

  /// Cloud Code: актуальная статистика продвижения/просмотров для карточки.
  Future<PromotionStats> getPromotionStats({
    required String userId,
    required String productId,
  });

  /// Создаёт заказ и возвращает URL оплаты. Деньги списывает провайдер на стороне сервера.
  Future<PromotionCheckoutSession> createCheckoutSession({
    required String productId,
    required ProductPromotionKind kind,
  });

  /// Проверка статуса после возврата пользователя из браузера (polling).
  Future<PromotionOrderStatus> getOrderStatus(String orderId);
}
