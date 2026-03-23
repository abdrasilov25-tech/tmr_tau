import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/product_promotion_kind.dart';
import '../../domain/entities/promotion_checkout_session.dart';
import '../../domain/entities/promotion_order_status.dart';
import '../../domain/entities/promotion_stats.dart';
import '../../domain/exceptions/monetization_exception.dart';
import '../../domain/repositories/product_monetization_repository.dart';

/// Реализация монетизации через Supabase Edge Functions.
///
/// **Безопасность:** секреты валидации платежей хранятся только в Secrets Edge Functions.
class ProductMonetizationRepositoryImpl implements ProductMonetizationRepository {
  ProductMonetizationRepositoryImpl(this._client);

  final SupabaseClient _client;

  @override
  Future<PromotionCheckoutSession> activatePromotion({
    required String userId,
    required String productId,
    required ProductPromotionKind promoType,
  }) async {
    throw MonetizationException(
      'Действие недоступно: используйте In-App Purchase PaymentService.',
    );
  }

  @override
  Future<PromotionStats> getPromotionStats({
    required String userId,
    required String productId,
  }) async {
    throw MonetizationException(
      'Действие недоступно: статистика платёжного провайдера удалена.',
    );
  }

  @override
  Future<PromotionCheckoutSession> createCheckoutSession({
    required String productId,
    required ProductPromotionKind kind,
  }) {
    final auth = _client.auth.currentUser;
    if (auth == null) {
      throw MonetizationException('Войдите в аккаунт снова (сессия недействительна).');
    }
    // Старый API оставлен для совместимости интерфейса.
    return activatePromotion(
      userId: auth.id,
      productId: productId,
      promoType: kind,
    );
  }


  @override
  Future<PromotionOrderStatus> getOrderStatus(String orderId) async {
    final row = await _client
        .from('product_promotion_orders')
        .select('id, status, provider_ref')
        .eq('id', orderId)
        .maybeSingle();
    if (row == null) {
      return PromotionOrderStatus(
        orderId: orderId,
        status: PromotionPaymentStatus.failed,
      );
    }
    final statusStr = (row['status'] as String?) ?? 'pending';
    final status = switch (statusStr) {
      'paid' => PromotionPaymentStatus.paid,
      'failed' => PromotionPaymentStatus.failed,
      'cancelled' => PromotionPaymentStatus.cancelled,
      _ => PromotionPaymentStatus.pending,
    };
    return PromotionOrderStatus(
      orderId: orderId,
      status: status,
      providerRef: row['provider_ref'] as String?,
    );
  }
}
