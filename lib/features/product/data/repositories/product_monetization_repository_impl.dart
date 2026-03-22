import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/product_promotion_kind.dart';
import '../../domain/entities/promotion_checkout_session.dart';
import '../../domain/entities/promotion_order_status.dart';
import '../../domain/exceptions/monetization_exception.dart';
import '../../domain/repositories/product_monetization_repository.dart';

/// Реализация монетизации через Supabase Edge Functions (`create-product-promotion`, опрос таблицы).
///
/// **Безопасность:** секреты Stripe / Halyk / Caspipay хранятся только в Secrets Edge Functions, не в приложении.
class ProductMonetizationRepositoryImpl implements ProductMonetizationRepository {
  ProductMonetizationRepositoryImpl(this._client);

  final SupabaseClient _client;

  static const String _fnCreateCheckout = 'create-product-promotion';

  @override
  Future<PromotionCheckoutSession> createCheckoutSession({
    required String productId,
    required ProductPromotionKind kind,
  }) async {
    try {
      final res = await _client.functions.invoke(
        _fnCreateCheckout,
        body: <String, dynamic>{
          'product_id': productId,
          'kind': kind.apiValue,
        },
      );
      final data = res.data;
      if (data is! Map) {
        throw MonetizationException('Некорректный ответ сервера оплаты');
      }
      final map = Map<String, dynamic>.from(data);
      final url = map['checkout_url'] as String?;
      final orderId = map['order_id'] as String?;
      final provider = map['provider'] as String? ?? 'stripe';
      if (url == null || url.isEmpty || orderId == null || orderId.isEmpty) {
        throw MonetizationException(
          'Не настроена Edge Function $_fnCreateCheckout. См. supabase/functions/README.md',
        );
      }
      return PromotionCheckoutSession(
        checkoutUrl: url,
        orderId: orderId,
        provider: provider,
        amountMinor: map['amount_minor'] as int?,
        currency: map['currency'] as String? ?? 'KZT',
      );
    } on FunctionException catch (e) {
      throw MonetizationException(_formatFunctionError(e));
    } catch (e) {
      throw MonetizationException(e.toString());
    }
  }

  /// Текст ошибки из ответа Edge Function (JSON `{ "error": "..." }`).
  static String _formatFunctionError(FunctionException e) {
    final d = e.details;
    if (d is Map && d['error'] != null) {
      return d['error'].toString();
    }
    if (d != null && '$d'.isNotEmpty) return d.toString();
    final rp = e.reasonPhrase;
    if (rp != null && rp.isNotEmpty) return rp;
    return 'Ошибка Edge Function';
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
