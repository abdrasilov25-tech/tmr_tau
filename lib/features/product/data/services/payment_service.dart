import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/qarmet_promotion_history_item.dart';
import '../../domain/entities/qarmet_product.dart';

enum PaymentResultStatus { success, cancelled, error }

class PaymentResult {
  const PaymentResult({required this.status, this.message});

  final PaymentResultStatus status;
  final String? message;
}

/// Единый сервис IAP (StoreKit / Google Play) + Cloud Code валидация в Supabase.
class PaymentService {
  PaymentService(this._client) : _iap = InAppPurchase.instance {
    _assertPackageValueLadder();
  }

  static const String promotionStartProductId = 'promotion_start';
  static const String promotionPremiumProductId = 'promotion_premium';
  static const String promotionBusinessProductId = 'promotion_business';
  static const String officialPageProductId = 'official_page';

  final SupabaseClient _client;
  final InAppPurchase _iap;

  List<ProductDetails> _products = const <ProductDetails>[];

  static const Map<String, QarmetProduct> _qarmetCatalog = {
    // Стартовый пакет: 3 Qarmet без бонуса.
    promotionStartProductId: QarmetProduct(
      productId: promotionStartProductId,
      title: 'Start',
      baseQarmet: 3,
      bonusQarmet: 0,
      priceKzt: 199,
    ),
    // Средний пакет: бонус мотивирует брать больше.
    promotionPremiumProductId: QarmetProduct(
      productId: promotionPremiumProductId,
      title: 'Premium',
      baseQarmet: 10,
      bonusQarmet: 2,
      priceKzt: 499,
    ),
    // Большой пакет: лучшая цена за 1 Qarmet.
    promotionBusinessProductId: QarmetProduct(
      productId: promotionBusinessProductId,
      title: 'Business',
      baseQarmet: 50,
      bonusQarmet: 5,
      priceKzt: 1299,
    ),
    // Подписка: ежемесячные Qarmet + постоянные преимущества.
    officialPageProductId: QarmetProduct(
      productId: officialPageProductId,
      title: 'Official Page',
      baseQarmet: 20,
      bonusQarmet: 5,
      priceKzt: 1999,
      isSubscription: true,
    ),
  };

  List<QarmetProduct> get catalog =>
      _qarmetCatalog.values.toList(growable: false);

  Future<void> initStore() async {
    final available = await _iap.isAvailable();
    if (!available) {
      throw Exception('Магазин покупок недоступен на устройстве');
    }

    final response = await _iap.queryProductDetails(
      _qarmetCatalog.keys.toSet(),
    );
    if (response.error != null) {
      throw Exception(response.error!.message);
    }
    _products = response.productDetails;
  }

  Future<PaymentResult> buyQarmetPackage(String productId) async {
    final package = _qarmetCatalog[productId];
    if (package == null) {
      return const PaymentResult(
        status: PaymentResultStatus.error,
        message: 'Неизвестный продукт Qarmet',
      );
    }
    return _purchase(
      storeProductId: productId,
      onVerified: (purchase) async {
        await _verifyPurchase(purchase, productId);
        await _creditPurchasedQarmet(package);
        if (package.isSubscription) {
          await _activateOfficialPageSubscription(package);
        }
      },
    );
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<int> getQarmetBalance() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return 0;
    final row = await _client
        .from('users')
        .select('qarmet_balance')
        .eq('id', auth.id)
        .maybeSingle();
    if (row == null) return 0;
    return row['qarmet_balance'] as int? ?? 0;
  }

  Future<bool> isOfficialPageActive() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return false;
    final row = await _client
        .from('users')
        .select('official_page_active')
        .eq('id', auth.id)
        .maybeSingle();
    return row?['official_page_active'] as bool? ?? false;
  }

  Future<void> ensureMonthlySubscriptionCredit() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return;
    final row = await _client
        .from('users')
        .select(
          'official_page_active, official_page_last_credit_at, qarmet_balance',
        )
        .eq('id', auth.id)
        .maybeSingle();
    if (row == null) return;
    final active = row['official_page_active'] as bool? ?? false;
    if (!active) return;
    final now = DateTime.now().toUtc();
    final lastRaw = row['official_page_last_credit_at'] as String?;
    final lastCreditAt = DateTime.tryParse(lastRaw ?? '')?.toUtc();
    if (lastCreditAt == null) return;
    final monthsPassed = now.difference(lastCreditAt).inDays ~/ 30;
    if (monthsPassed <= 0) return;
    final subscriptionPack = _qarmetCatalog[officialPageProductId]!;
    final monthlyCredit = subscriptionPack.totalQarmet * monthsPassed;
    final currentBalance = row['qarmet_balance'] as int? ?? 0;
    await _client
        .from('users')
        .update({
          'qarmet_balance': currentBalance + monthlyCredit,
          'official_page_last_credit_at': now.toIso8601String(),
        })
        .eq('id', auth.id);
    debugPrint(
      'Qarmet monthly credit: +$monthlyCredit (${subscriptionPack.baseQarmet}+${subscriptionPack.bonusQarmet} x $monthsPassed)',
    );
  }

  Future<void> spendForProductPromotion({
    required String productId,
    required int positions,
  }) async {
    if (positions <= 0) {
      throw Exception('Количество позиций должно быть больше 0');
    }
    final cost = positions;
    await _spendQarmet(cost, reason: 'promotion_positions');

    final row = await _client
        .from('products')
        .select('promo_top_until')
        .eq('id', productId)
        .maybeSingle();
    final now = DateTime.now().toUtc();
    DateTime base = now;
    if (row != null) {
      final raw = row['promo_top_until'] as String?;
      final until = DateTime.tryParse(raw ?? '')?.toUtc();
      if (until != null && until.isAfter(now)) {
        base = until;
      }
    }
    final updatedUntil = base.add(Duration(hours: positions));
    await _client
        .from('products')
        .update({
          'is_top': true,
          'promo_top_until': updatedUntil.toIso8601String(),
        })
        .eq('id', productId);
  }

  Future<void> spendForTopPromotion(String productId) async {
    await _activatePromotion(
      productId: productId,
      promoUntilColumn: 'promo_top_until',
      reason: 'promotion_top',
      setFlags: const <String, dynamic>{'is_top': true},
    );
  }

  Future<void> spendForUrgentPromotion(String productId) async {
    await _activatePromotion(
      productId: productId,
      promoUntilColumn: 'promo_urgent_until',
      reason: 'promotion_urgent',
      setFlags: const <String, dynamic>{'is_urgent': true},
    );
  }

  Future<void> spendForHighlightPromotion(String productId) async {
    await _activatePromotion(
      productId: productId,
      promoUntilColumn: 'promo_highlight_until',
      reason: 'promotion_highlight',
    );
  }

  Future<List<QarmetPromotionHistoryItem>> getMyPromotionHistory() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return const <QarmetPromotionHistoryItem>[];
    final rows = await _client
        .from('products')
        .select(
          'id,title,is_top,is_urgent,promo_top_until,promo_urgent_until,promo_highlight_until',
        )
        .eq('seller_id', auth.id)
        .order('created_at', ascending: false);
    final now = DateTime.now().toUtc();
    final list = <QarmetPromotionHistoryItem>[];
    for (final raw in (rows as List<dynamic>)) {
      final row = Map<String, dynamic>.from(raw as Map);
      final topUntil = DateTime.tryParse(
        (row['promo_top_until'] ?? '').toString(),
      )?.toUtc();
      final urgentUntil = DateTime.tryParse(
        (row['promo_urgent_until'] ?? '').toString(),
      )?.toUtc();
      final highlightUntil = DateTime.tryParse(
        (row['promo_highlight_until'] ?? '').toString(),
      )?.toUtc();
      final isTop =
          (row['is_top'] as bool? ?? false) ||
          (topUntil != null && topUntil.isAfter(now));
      final isUrgent =
          (row['is_urgent'] as bool? ?? false) ||
          (urgentUntil != null && urgentUntil.isAfter(now));
      final isHighlight = highlightUntil != null && highlightUntil.isAfter(now);
      final item = QarmetPromotionHistoryItem(
        productId: row['id'] as String,
        title: (row['title'] as String?) ?? 'Без названия',
        isTopActive: isTop,
        isUrgentActive: isUrgent,
        isHighlightActive: isHighlight,
        promoTopUntil: topUntil,
        promoUrgentUntil: urgentUntil,
        promoHighlightUntil: highlightUntil,
      );
      final hadAnyPromotion =
          (row['is_top'] as bool? ?? false) ||
          (row['is_urgent'] as bool? ?? false) ||
          topUntil != null ||
          urgentUntil != null ||
          highlightUntil != null;
      if (hadAnyPromotion) {
        list.add(item);
      }
    }
    return list;
  }

  Future<void> spendForPremiumBadge({required int cost}) async {
    await _spendQarmet(cost, reason: 'profile_premium_badge');
    final auth = _requireAuthUser();
    await _client
        .from('users')
        .update({'profile_premium_badge': true})
        .eq('id', auth.id);
  }

  Future<void> spendForFrame({
    required int frameLevel,
    required int cost,
  }) async {
    await _spendQarmet(cost, reason: 'profile_frame');
    final auth = _requireAuthUser();
    await _client
        .from('users')
        .update({'profile_frame_level': frameLevel})
        .eq('id', auth.id);
  }

  Future<void> spendForBadge({
    required int badgeLevel,
    required int cost,
  }) async {
    await _spendQarmet(cost, reason: 'profile_badge');
    final auth = _requireAuthUser();
    await _client
        .from('users')
        .update({'profile_badge_level': badgeLevel})
        .eq('id', auth.id);
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
      final isSubscription =
          _qarmetCatalog[storeProductId]?.isSubscription ?? false;
      final ok = isSubscription
          ? await _iap.buyNonConsumable(purchaseParam: param)
          : await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
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

  Future<void> _creditPurchasedQarmet(QarmetProduct package) async {
    final amount = package.totalQarmet;
    await _creditQarmet(
      amount,
      reason: package.productId,
      baseAmount: package.baseQarmet,
      bonusAmount: package.bonusQarmet,
    );
  }

  Future<void> _activateOfficialPageSubscription(QarmetProduct package) async {
    final auth = _requireAuthUser();
    final now = DateTime.now().toUtc();
    await _client
        .from('users')
        .update({
          'official_page_active': true,
          'official_page_profile_perks': true,
          'official_page_promo_perks': true,
          'official_page_last_credit_at': now.toIso8601String(),
        })
        .eq('id', auth.id);
    debugPrint(
      'Official page activated: monthly ${package.totalQarmet} Qarmet + perks',
    );
  }

  Future<void> _creditQarmet(
    int amount, {
    required String reason,
    int? baseAmount,
    int? bonusAmount,
  }) async {
    final auth = _requireAuthUser();
    final row = await _client
        .from('users')
        .select('qarmet_balance')
        .eq('id', auth.id)
        .maybeSingle();
    final current = row?['qarmet_balance'] as int? ?? 0;
    final next = current + amount;
    await _client
        .from('users')
        .update({'qarmet_balance': next})
        .eq('id', auth.id);
    debugPrint(
      'Qarmet credited: +$amount (base=${baseAmount ?? amount}, bonus=${bonusAmount ?? 0}) reason=$reason balance=$next',
    );
  }

  Future<void> _activatePromotion({
    required String productId,
    required String promoUntilColumn,
    required String reason,
    Map<String, dynamic> setFlags = const <String, dynamic>{},
  }) async {
    // Любое продвижение товара стоит ровно 1 Qarmet.
    await _spendQarmet(1, reason: reason);

    final row = await _client
        .from('products')
        .select(promoUntilColumn)
        .eq('id', productId)
        .maybeSingle();
    final now = DateTime.now().toUtc();
    DateTime base = now;
    if (row != null) {
      final raw = row[promoUntilColumn] as String?;
      final until = DateTime.tryParse(raw ?? '')?.toUtc();
      if (until != null && until.isAfter(now)) {
        base = until;
      }
    }
    final nextUntil = base.add(const Duration(hours: 24));
    await _client
        .from('products')
        .update({...setFlags, promoUntilColumn: nextUntil.toIso8601String()})
        .eq('id', productId);
    debugPrint(
      'Promotion activated: product=$productId type=$reason cost=1 nextUntil=$nextUntil',
    );
  }

  Future<void> _spendQarmet(int amount, {required String reason}) async {
    if (amount <= 0) {
      throw Exception('Сумма списания должна быть больше 0');
    }
    final auth = _requireAuthUser();
    final row = await _client
        .from('users')
        .select('qarmet_balance')
        .eq('id', auth.id)
        .maybeSingle();
    final current = row?['qarmet_balance'] as int? ?? 0;
    if (current < amount) {
      throw Exception(
        'Недостаточно Qarmet. Нужно: $amount, доступно: $current',
      );
    }
    final next = current - amount;
    await _client
        .from('users')
        .update({'qarmet_balance': next})
        .eq('id', auth.id);
    debugPrint('Qarmet spent: -$amount reason=$reason balance=$next');
  }

  User _requireAuthUser() {
    final auth = _client.auth.currentUser;
    if (auth == null) {
      throw Exception('Пользователь не авторизован');
    }
    return auth;
  }

  void _assertPackageValueLadder() {
    final premium = _qarmetCatalog[promotionPremiumProductId]!;
    final business = _qarmetCatalog[promotionBusinessProductId]!;
    if (business.pricePerQarmet >= premium.pricePerQarmet) {
      throw StateError(
        'promotion_business должен быть выгоднее promotion_premium по цене за 1 Qarmet',
      );
    }
  }

  Future<void> _verifyPurchase(
    PurchaseDetails purchase,
    String productId,
  ) async {
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
}
