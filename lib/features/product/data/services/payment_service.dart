import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum PaymentResultStatus { success, cancelled, error }

class PaymentResult {
  const PaymentResult({
    required this.status,
    this.message,
  });

  final PaymentResultStatus status;
  final String? message;
}

/// Единый сервис IAP (StoreKit / Google Play) + Cloud Code валидация в Supabase.
class PaymentService {
  PaymentService(this._client) : _iap = InAppPurchase.instance;

  static const String boostProductId = 'boost_post';
  static const String premiumProductId = 'premium_subscription';

  final SupabaseClient _client;
  final InAppPurchase _iap;

  List<ProductDetails> _products = const <ProductDetails>[];

  Future<void> initStore() async {
    final available = await _iap.isAvailable();
    if (!available) {
      throw Exception('Магазин покупок недоступен на устройстве');
    }

    final response = await _iap.queryProductDetails(
      <String>{boostProductId, premiumProductId},
    );
    if (response.error != null) {
      throw Exception(response.error!.message);
    }
    _products = response.productDetails;
  }

  Future<PaymentResult> buyBoost({
    required String postId,
    String productId = boostProductId,
  }) async {
    if (await _isBoostActive(postId)) {
      return const PaymentResult(
        status: PaymentResultStatus.error,
        message: 'Boost уже активен для этого товара',
      );
    }
    return _purchase(
      storeProductId: productId,
      onVerified: (purchase) async {
        await _verifyPurchase(purchase, productId);
        await _updateBoostStatus(postId);
      },
    );
  }

  Future<PaymentResult> buyPremium({
    String productId = premiumProductId,
  }) async {
    if (await _hasActivePremium()) {
      return const PaymentResult(
        status: PaymentResultStatus.error,
        message: 'Премиум уже активен',
      );
    }
    return _purchase(
      storeProductId: productId,
      onVerified: (purchase) async {
        await _verifyPurchase(purchase, productId);
        await _updateUserPremium();
      },
    );
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<PaymentResult> _purchase({
    required String storeProductId,
    required Future<void> Function(PurchaseDetails) onVerified,
  }) async {
    if (_products.isEmpty) {
      await initStore();
    }
    ProductDetails? product;
    for (final p in _products) {
      if (p.id == storeProductId) {
        product = p;
        break;
      }
    }
    if (product == null) {
      return PaymentResult(
        status: PaymentResultStatus.error,
        message: 'Продукт $storeProductId не найден в магазине',
      );
    }

    final completer = Completer<PaymentResult>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _iap.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          if (purchase.productID != storeProductId) continue;

          try {
            switch (purchase.status) {
              case PurchaseStatus.pending:
                break;
              case PurchaseStatus.purchased:
              case PurchaseStatus.restored:
                await onVerified(purchase);
                if (purchase.pendingCompletePurchase) {
                  await _iap.completePurchase(purchase);
                }
                if (!completer.isCompleted) {
                  completer.complete(
                    const PaymentResult(status: PaymentResultStatus.success),
                  );
                }
                break;
              case PurchaseStatus.canceled:
                if (!completer.isCompleted) {
                  completer.complete(
                    const PaymentResult(
                      status: PaymentResultStatus.cancelled,
                      message: 'Покупка отменена',
                    ),
                  );
                }
                break;
              case PurchaseStatus.error:
                if (!completer.isCompleted) {
                  completer.complete(
                    PaymentResult(
                      status: PaymentResultStatus.error,
                      message: purchase.error?.message ?? 'Ошибка покупки',
                    ),
                  );
                }
                break;
            }
          } catch (e, st) {
            debugPrint('IAP processing error: $e\n$st');
            if (!completer.isCompleted) {
              completer.complete(
                PaymentResult(
                  status: PaymentResultStatus.error,
                  message: 'Ошибка обработки покупки: $e',
                ),
              );
            }
          }
        }
      },
      onError: (e, st) {
        debugPrint('IAP stream error: $e\n$st');
        if (!completer.isCompleted) {
          completer.complete(
            PaymentResult(
              status: PaymentResultStatus.error,
              message: 'Ошибка потока покупок: $e',
            ),
          );
        }
      },
    );

    try {
      final param = PurchaseParam(productDetails: product);
      final ok = await _iap.buyNonConsumable(purchaseParam: param);
      if (!ok && !completer.isCompleted) {
        completer.complete(
          const PaymentResult(
            status: PaymentResultStatus.error,
            message: 'Не удалось начать покупку',
          ),
        );
      }
      return await completer.future.timeout(
        const Duration(minutes: 3),
        onTimeout: () => const PaymentResult(
          status: PaymentResultStatus.error,
          message: 'Таймаут ожидания результата покупки',
        ),
      );
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _verifyPurchase(PurchaseDetails purchase, String productId) async {
    final auth = _client.auth.currentUser;
    if (auth == null) throw Exception('Пользователь не авторизован');

    await _client.functions.invoke(
      'verifyPurchase',
      body: <String, dynamic>{
        'userId': auth.id,
        'productId': productId,
        'purchaseId': purchase.purchaseID,
        'transactionDate': purchase.transactionDate,
        'verificationData': purchase.verificationData.serverVerificationData,
        'source': purchase.verificationData.source,
        'platform': defaultTargetPlatform.name,
      },
    );
  }

  Future<void> _updateUserPremium() async {
    final auth = _client.auth.currentUser;
    if (auth == null) throw Exception('Пользователь не авторизован');
    await _client.functions.invoke(
      'updateUserPremium',
      body: <String, dynamic>{'userId': auth.id},
    );
  }

  Future<void> _updateBoostStatus(String postId) async {
    await _client.functions.invoke(
      'updateBoostStatus',
      body: <String, dynamic>{'postId': postId},
    );
  }

  Future<bool> _isBoostActive(String postId) async {
    final row = await _client
        .from('products')
        .select('boosted, is_top, promo_top_until')
        .eq('id', postId)
        .maybeSingle();
    if (row == null) return false;
    final boosted = row['boosted'] as bool? ?? false;
    if (boosted) return true;
    final isTop = row['is_top'] as bool? ?? false;
    if (isTop) return true;
    final until = row['promo_top_until'] as String?;
    if (until != null) {
      final t = DateTime.tryParse(until);
      if (t != null && t.toUtc().isAfter(DateTime.now().toUtc())) return true;
    }
    return false;
  }

  Future<bool> _hasActivePremium() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return false;
    final row = await _client
        .from('users')
        .select('is_premium, premium_until')
        .eq('id', auth.id)
        .maybeSingle();
    if (row == null) return false;
    final isPremium = row['is_premium'] as bool? ?? false;
    if (!isPremium) return false;
    final until = row['premium_until'] as String?;
    if (until == null) return isPremium;
    final t = DateTime.tryParse(until);
    if (t == null) return isPremium;
    return t.toUtc().isAfter(DateTime.now().toUtc());
  }
}
