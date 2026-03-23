import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/product_promotion_kind.dart';
import '../../domain/entities/promotion_checkout_session.dart';
import '../../domain/entities/promotion_order_status.dart';
import '../../domain/entities/promotion_stats.dart';
import '../../domain/exceptions/monetization_exception.dart';
import '../../domain/repositories/product_monetization_repository.dart';

/// Реализация монетизации через Supabase Edge Functions (`create-product-promotion`, опрос таблицы).
///
/// **Безопасность:** секреты Stripe / Halyk / Caspipay хранятся только в Secrets Edge Functions, не в приложении.
class ProductMonetizationRepositoryImpl implements ProductMonetizationRepository {
  ProductMonetizationRepositoryImpl(this._client);

  final SupabaseClient _client;

  static const String _fnCreateCheckout = 'create-product-promotion';
  static const String _fnActivatePromotion = 'activatePromotion';
  static const String _fnGetPromotionStats = 'getPromotionStats';

  @override
  Future<PromotionCheckoutSession> activatePromotion({
    required String userId,
    required String productId,
    required ProductPromotionKind promoType,
  }) async {
    try {
      await _ensureFreshSession();
      final session = _client.auth.currentSession;
      if (session == null) {
        throw MonetizationException(
          'Войдите в аккаунт снова (сессия недействительна).',
        );
      }
      final res = await _client.functions.invoke(
        _fnActivatePromotion,
        body: <String, dynamic>{
          'userId': userId,
          'productId': productId,
          'promoType': promoType.apiValue,
        },
        headers: <String, String>{
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );
      return _parseCheckoutResponse(res.data);
    } on FunctionException catch (e) {
      throw MonetizationException(_formatFunctionError(e));
    } on MonetizationException {
      rethrow;
    } catch (e) {
      throw MonetizationException(e.toString());
    }
  }

  @override
  Future<PromotionStats> getPromotionStats({
    required String userId,
    required String productId,
  }) async {
    try {
      await _ensureFreshSession();
      final session = _client.auth.currentSession;
      if (session == null) {
        throw MonetizationException(
          'Войдите в аккаунт снова (сессия недействительна).',
        );
      }
      final res = await _client.functions.invoke(
        _fnGetPromotionStats,
        body: <String, dynamic>{
          'userId': userId,
          'productId': productId,
        },
        headers: <String, String>{
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );
      final data = res.data;
      if (data is! Map) {
        throw MonetizationException('Некорректный ответ Cloud Code статистики');
      }
      return PromotionStats.fromJson(Map<String, dynamic>.from(data));
    } on FunctionException catch (e) {
      throw MonetizationException(_formatFunctionError(e));
    } on MonetizationException {
      rethrow;
    } catch (e) {
      throw MonetizationException(e.toString());
    }
  }

  @override
  Future<PromotionCheckoutSession> createCheckoutSession({
    required String productId,
    required ProductPromotionKind kind,
  }) async {
    try {
      // Edge Function с verify_jwt=true — без валидного access token шлюз отвечает 401 Invalid JWT.
      await _ensureFreshSession();
      final session = _client.auth.currentSession;
      if (session == null) {
        throw MonetizationException(
          'Войдите в аккаунт снова (сессия недействительна).',
        );
      }
      final res = await _client.functions.invoke(
        _fnCreateCheckout,
        body: <String, dynamic>{
          'product_id': productId,
          'kind': kind.apiValue,
        },
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );
      return _parseCheckoutResponse(res.data);
    } on MonetizationException {
      rethrow;
    } on FunctionException catch (e) {
      throw MonetizationException(_formatFunctionError(e));
    } catch (e) {
      throw MonetizationException(e.toString());
    }
  }

  /// Пытается обновить access token (иначе шлюз Edge Functions может ответить 401 Invalid JWT).
  Future<void> _ensureFreshSession() async {
    if (_client.auth.currentSession == null) return;
    try {
      await _client.auth.refreshSession();
    } catch (_) {
      // Нет refresh token или сессия недействительна — ниже проверим currentSession
    }
  }

  PromotionCheckoutSession _parseCheckoutResponse(dynamic data) {
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
  }

  /// Текст ошибки из ответа Edge Function (JSON `{ "error": "..." }` и шлюз Supabase).
  static String _formatFunctionError(FunctionException e) {
    final d = e.details;
    if (d is Map) {
      if (d['error'] != null) return d['error'].toString();
      if (d['message'] != null) return d['message'].toString();
      if (d['msg'] != null) return d['msg'].toString();
    }
    if (e.status == 401) {
      return 'Сессия недействительна (401). Выйдите из аккаунта и войдите снова. '
          'Проверь, что в .env верные SUPABASE_URL и SUPABASE_ANON_KEY этого проекта.';
    }
    if (d != null && '$d'.isNotEmpty) return d.toString();
    final rp = e.reasonPhrase;
    if (rp != null && rp.isNotEmpty) return rp;
    return 'Ошибка Edge Function (HTTP ${e.status})';
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
