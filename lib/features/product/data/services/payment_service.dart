import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/qarmet_promotion_history_item.dart';
import '../../domain/entities/qarmet_product.dart';

enum PaymentResultStatus { success, cancelled, error }

class PaymentResult {
  const PaymentResult({required this.status, this.message});

  final PaymentResultStatus status;
  final String? message;
}

class WalletSnapshot {
  const WalletSnapshot({
    required this.balance,
    required this.isOfficialPageActive,
    required this.cosmeticsLifetimeUnlocked,
    required this.promotionHistory,
    required this.catalog,
    required this.fetchedAt,
  });

  final int balance;
  final bool isOfficialPageActive;
  /// IAP «навсегда»: рамки, значок, галочка в профиле + стикеры на карте без Qarmet.
  final bool cosmeticsLifetimeUnlocked;
  final List<QarmetPromotionHistoryItem> promotionHistory;
  final List<QarmetProduct> catalog;
  final DateTime fetchedAt;
}

/// Единый сервис IAP (StoreKit / Google Play) + Cloud Code валидация в Supabase.
class PaymentService {
  PaymentService(this._client) : _iap = InAppPurchase.instance {
    _assertPackageValueLadder();
  }

  static const String promotionStartProductId = 'qarmet_10';
  static const String promotionPremiumProductId = 'qarmet_20';
  static const String promotionBusinessProductId = 'qarmet_30';
  /// App Store Connect: auto-renewable subscription (Official Page / карта).
  /// Должен **посимвольно** совпадать с Product ID в ASC для приложения `com.bazar.tmr-tau`.
  static const String officialPageProductId =
      'com.bazar.tmrtau.subscription.monthly';
  static const String premiumSubscriptionProductId = 'premium_subscription';
  static const String promotePostProductId = 'promote_post';
  /// Non-consumable: оформление профиля (рамки, бейджи, галочка) + стикеры на карте.
  static const String profileCosmeticsLifetimeProductId =
      'com.bazar.tmrtau.premium';

  /// Уровни, выставляемые на сервере при успешной покупке [profileCosmeticsLifetimeProductId].
  static const int profileCosmeticsIapMaxFrameLevel = 3;
  static const int profileCosmeticsIapMaxBadgeLevel = 3;

  final SupabaseClient _client;
  final InAppPurchase _iap;

  List<ProductDetails> _products = const <ProductDetails>[];
  bool _storeAvailable = false;
  String? _storeInitError;
  WalletSnapshot? _walletCache;
  DateTime? _lastMonthlyCreditCheckAt;
  static const String _walletCachePrefix = 'qarmet_wallet_snapshot_v1_';

  static const Map<String, QarmetProduct> _qarmetCatalog = {
    // LIVE-battle mapping: qarmet_10 -> 100.
    promotionStartProductId: QarmetProduct(
      productId: promotionStartProductId,
      title: 'Start',
      baseQarmet: 100,
      bonusQarmet: 0,
      priceKzt: 199,
    ),
    // LIVE-battle mapping: qarmet_20 -> 250.
    promotionPremiumProductId: QarmetProduct(
      productId: promotionPremiumProductId,
      title: 'Premium',
      baseQarmet: 250,
      bonusQarmet: 0,
      priceKzt: 499,
    ),
    // LIVE-battle mapping: qarmet_30 -> 400.
    promotionBusinessProductId: QarmetProduct(
      productId: promotionBusinessProductId,
      title: 'Business',
      baseQarmet: 400,
      bonusQarmet: 0,
      priceKzt: 1299,
    ),
    // Месячная подписка Official Page (Store); ежемесячные Qarmet — RPC credit_official_page_monthly_qarmet.
    officialPageProductId: QarmetProduct(
      productId: officialPageProductId,
      title: 'Official Page',
      baseQarmet: 700,
      bonusQarmet: 0,
      priceKzt: 1999,
      isSubscription: true,
    ),
  };

  static const Set<String> _extraIapProductIds = <String>{
    premiumSubscriptionProductId,
    promotePostProductId,
    profileCosmeticsLifetimeProductId,
  };

  List<QarmetProduct> get catalog =>
      _qarmetCatalog.values.toList(growable: false);

  String? get storeInitError => _storeInitError;

  Future<void> initStore() async {
    try {
      final available = await _iap.isAvailable();
      _storeAvailable = available;
      if (!available) {
        _products = const <ProductDetails>[];
        _storeInitError = 'Магазин покупок недоступен на устройстве';
        debugPrint('IAP init: store unavailable');
        return;
      }

      final response = await _iap.queryProductDetails(
        {..._qarmetCatalog.keys, ..._extraIapProductIds},
      );
      if (response.error != null) {
        _products = const <ProductDetails>[];
        _storeInitError =
            _friendlyIapUserMessage(response.error!.message);
        debugPrint('IAP init queryProductDetails error: ${response.error}');
        return;
      }
      _products = response.productDetails;
      final notFound = response.notFoundIDs;
      if (notFound.isNotEmpty) {
        debugPrint('IAP notFoundIDs (нет в ASC или неверный id): $notFound');
      }
      if (_products.isEmpty) {
        _storeInitError = notFound.isEmpty
            ? 'Не удалось получить товары из App Store. Проверьте сеть, Sandbox и capability In‑App Purchase.'
            : 'В App Store не найдены товары: ${notFound.join(", ")}. '
                'Создайте в App Store Connect In‑App Purchase с **такими же** Product ID или измените константы в PaymentService.';
      } else {
        _storeInitError = null;
      }
    } catch (e, st) {
      _products = const <ProductDetails>[];
      _storeAvailable = false;
      _storeInitError = e is PlatformException
          ? _friendlyStoreError(e)
          : _friendlyIapUserMessage(e.toString());
      debugPrint('IAP init failed: $e\n$st');
    }
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
      },
    );
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<bool> isPremiumActive() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return false;
    try {
      final row = await _client
          .from('users')
          .select('premium_active,premium_until,official_page_active')
          .eq('id', auth.id)
          .maybeSingle();
      if (row == null) return false;
      final active = row['premium_active'] as bool? ?? false;
      final untilRaw = row['premium_until'] as String?;
      final until = DateTime.tryParse(untilRaw ?? '')?.toUtc();
      final byDate = until != null && until.isAfter(DateTime.now().toUtc());
      return active || byDate || (row['official_page_active'] as bool? ?? false);
    } catch (_) {
      return isOfficialPageActive();
    }
  }

  Future<PaymentResult> purchasePremium() async {
    return _purchase(
      storeProductId: premiumSubscriptionProductId,
      onVerified: (purchase) async {
        await _verifyPurchase(purchase, premiumSubscriptionProductId);
        final auth = _requireAuthUser();
        final until = DateTime.now().toUtc().add(const Duration(days: 30));
        await _client.from('users').update({
          'premium_active': true,
          'premium_until': until.toIso8601String(),
        }).eq('id', auth.id);
      },
    );
  }

  Future<PaymentResult> purchasePromotePost({
    required String postId,
    Duration duration = const Duration(hours: 24),
  }) async {
    return _purchase(
      storeProductId: promotePostProductId,
      onVerified: (purchase) async {
        await _verifyPurchase(purchase, promotePostProductId);
        final until = DateTime.now().toUtc().add(duration).toIso8601String();
        await _client.from('posts').update({
          'is_promoted': true,
          'promoted_until': until,
        }).eq('id', postId);
      },
    );
  }

  /// Non-consumable IAP: рамки, значки, галочка в профиле и стикеры на карте (без Qarmet).
  Future<PaymentResult> purchaseProfileCosmeticsLifetime() async {
    return _purchase(
      storeProductId: profileCosmeticsLifetimeProductId,
      onVerified: (purchase) async {
        await _verifyPurchase(purchase, profileCosmeticsLifetimeProductId);
      },
    );
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

  Future<bool> getCosmeticsLifetimeUnlocked() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return false;
    final row = await _client
        .from('users')
        .select('profile_cosmetics_iap_forever')
        .eq('id', auth.id)
        .maybeSingle();
    return row?['profile_cosmetics_iap_forever'] as bool? ?? false;
  }

  Future<void> ensureMonthlySubscriptionCredit() async {
    final now = DateTime.now().toUtc();
    final lastCheck = _lastMonthlyCreditCheckAt;
    if (lastCheck != null && now.difference(lastCheck) < const Duration(minutes: 10)) {
      return;
    }
    _lastMonthlyCreditCheckAt = now;

    final auth = _client.auth.currentUser;
    if (auth == null) return;
    try {
      await _client.rpc<int>('credit_official_page_monthly_qarmet');
    } on PostgrestException catch (e) {
      debugPrint(
        'Monthly Qarmet credit skipped: ${e.message.isNotEmpty ? e.message : e.code}',
      );
    }
  }

  WalletSnapshot? getCachedWalletSnapshot({
    Duration maxAge = const Duration(minutes: 2),
  }) {
    final cached = _walletCache;
    if (cached == null) return null;
    final age = DateTime.now().toUtc().difference(cached.fetchedAt.toUtc());
    if (age > maxAge) return null;
    return cached;
  }

  Future<WalletSnapshot?> getPersistentWalletSnapshot({
    Duration maxAge = const Duration(minutes: 30),
  }) async {
    final auth = _client.auth.currentUser;
    if (auth == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_walletCachePrefix${auth.id}');
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = DateTime.tryParse((json['fetched_at'] ?? '').toString());
      if (fetchedAt == null) return null;
      final age = DateTime.now().toUtc().difference(fetchedAt.toUtc());
      if (age > maxAge) return null;

      final historyRaw = json['promotion_history'];
      final history = <QarmetPromotionHistoryItem>[];
      if (historyRaw is List) {
        for (final e in historyRaw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          history.add(
            QarmetPromotionHistoryItem(
              productId: (m['product_id'] ?? '').toString(),
              title: (m['title'] as String?) ?? 'Без названия',
              isTopActive: m['is_top_active'] == true,
              isUrgentActive: m['is_urgent_active'] == true,
              isHighlightActive: m['is_highlight_active'] == true,
              promoTopUntil:
                  DateTime.tryParse((m['promo_top_until'] ?? '').toString()),
              promoUrgentUntil:
                  DateTime.tryParse((m['promo_urgent_until'] ?? '').toString()),
              promoHighlightUntil: DateTime.tryParse(
                (m['promo_highlight_until'] ?? '').toString(),
              ),
            ),
          );
        }
      }
      final snapshot = WalletSnapshot(
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        isOfficialPageActive: json['official_page_active'] == true,
        cosmeticsLifetimeUnlocked:
            json['cosmetics_lifetime_unlocked'] == true,
        promotionHistory: history,
        catalog: catalog,
        fetchedAt: fetchedAt,
      );
      _walletCache = snapshot;
      return snapshot;
    } catch (_) {
      return null;
    }
  }

  Future<WalletSnapshot> loadWalletSnapshot({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = getCachedWalletSnapshot();
      if (cached != null) return cached;
    }
    await ensureMonthlySubscriptionCredit();
    final results = await Future.wait<Object>([
      getQarmetBalance(),
      isOfficialPageActive(),
      getCosmeticsLifetimeUnlocked(),
      getMyPromotionHistory(),
    ]);
    final snapshot = WalletSnapshot(
      balance: results[0] as int,
      isOfficialPageActive: results[1] as bool,
      cosmeticsLifetimeUnlocked: results[2] as bool,
      promotionHistory: results[3] as List<QarmetPromotionHistoryItem>,
      catalog: catalog,
      fetchedAt: DateTime.now().toUtc(),
    );
    _walletCache = snapshot;
    await _savePersistentWalletSnapshot(snapshot);
    return snapshot;
  }

  Future<void> _savePersistentWalletSnapshot(WalletSnapshot snapshot) async {
    final auth = _client.auth.currentUser;
    if (auth == null) return;
    final payload = <String, dynamic>{
      'balance': snapshot.balance,
      'official_page_active': snapshot.isOfficialPageActive,
      'cosmetics_lifetime_unlocked': snapshot.cosmeticsLifetimeUnlocked,
      'fetched_at': snapshot.fetchedAt.toUtc().toIso8601String(),
      'promotion_history': snapshot.promotionHistory
          .map(
            (e) => <String, dynamic>{
              'product_id': e.productId,
              'title': e.title,
              'is_top_active': e.isTopActive,
              'is_urgent_active': e.isUrgentActive,
              'is_highlight_active': e.isHighlightActive,
              'promo_top_until': e.promoTopUntil?.toUtc().toIso8601String(),
              'promo_urgent_until': e.promoUrgentUntil?.toUtc().toIso8601String(),
              'promo_highlight_until':
                  e.promoHighlightUntil?.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_walletCachePrefix${auth.id}',
        jsonEncode(payload),
      );
    } catch (_) {
      // Non-critical optimization path.
    }
  }

  Future<void> spendForProductPromotion({
    required String productId,
    required int positions,
  }) async {
    if (positions <= 0) {
      throw Exception('Количество позиций должно быть больше 0');
    }
    await _activatePromotionAtomic(
      productId: productId,
      kind: 'top',
      cost: positions,
      durationHours: positions,
    );
  }

  Future<void> spendForTopPromotion(String productId) async {
    await _activatePromotionAtomic(
      productId: productId,
      kind: 'top',
      cost: 1,
      durationHours: 24,
    );
  }

  Future<void> spendForUrgentPromotion(String productId) async {
    await _activatePromotionAtomic(
      productId: productId,
      kind: 'urgent',
      cost: 1,
      durationHours: 24,
    );
  }

  Future<void> spendForHighlightPromotion(String productId) async {
    await _activatePromotionAtomic(
      productId: productId,
      kind: 'highlight',
      cost: 1,
      durationHours: 24,
    );
  }

  Future<void> spendForAllInOnePromotion(String productId) async {
    await _activatePromotionAtomic(
      productId: productId,
      kind: 'all_in_one',
      cost: 2,
      durationHours: 24,
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
    final auth = _requireAuthUser();
    if (await getCosmeticsLifetimeUnlocked()) {
      await _client
          .from('users')
          .update({'profile_premium_badge': true})
          .eq('id', auth.id);
      return;
    }
    await _spendQarmet(cost, reason: 'profile_premium_badge');
    await _client
        .from('users')
        .update({'profile_premium_badge': true})
        .eq('id', auth.id);
  }

  Future<void> spendForFrame({
    required int frameLevel,
    required int cost,
  }) async {
    final auth = _requireAuthUser();
    if (await getCosmeticsLifetimeUnlocked()) {
      final row = await _client
          .from('users')
          .select('profile_frame_level')
          .eq('id', auth.id)
          .maybeSingle();
      final current = row?['profile_frame_level'] as int? ?? 0;
      final capped = frameLevel.clamp(0, profileCosmeticsIapMaxFrameLevel);
      final next = capped > current ? capped : current;
      await _client
          .from('users')
          .update({'profile_frame_level': next})
          .eq('id', auth.id);
      return;
    }
    await _spendQarmet(cost, reason: 'profile_frame');
    await _client
        .from('users')
        .update({'profile_frame_level': frameLevel})
        .eq('id', auth.id);
  }

  Future<void> spendForBadge({
    required int badgeLevel,
    required int cost,
  }) async {
    final auth = _requireAuthUser();
    if (await getCosmeticsLifetimeUnlocked()) {
      final row = await _client
          .from('users')
          .select('profile_badge_level')
          .eq('id', auth.id)
          .maybeSingle();
      final current = row?['profile_badge_level'] as int? ?? 0;
      final capped = badgeLevel.clamp(0, profileCosmeticsIapMaxBadgeLevel);
      final next = capped > current ? capped : current;
      await _client
          .from('users')
          .update({'profile_badge_level': next})
          .eq('id', auth.id);
      return;
    }
    await _spendQarmet(cost, reason: 'profile_badge');
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
    if (!_storeAvailable || _products.isEmpty) {
      return PaymentResult(
        status: PaymentResultStatus.error,
        message: _storeInitError ??
            'Магазин покупок временно недоступен. Попробуйте позже.',
      );
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
                      message: _friendlyIapUserMessage(purchase.error?.message),
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
          final msg = e is PlatformException
              ? _friendlyStoreError(e)
              : _friendlyIapUserMessage(e.toString());
          completer.complete(
            PaymentResult(
              status: PaymentResultStatus.error,
              message: msg,
            ),
          );
        }
      },
    );

    try {
      final nonConsumable = _storeKitUseNonConsumable(storeProductId);
      final ok = await _startPurchaseWithRetry(
        product: product,
        nonConsumable: nonConsumable,
        storeProductId: storeProductId,
      );
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
    } on PlatformException catch (e) {
      return PaymentResult(
        status: PaymentResultStatus.error,
        message: _friendlyStoreError(e),
      );
    } catch (e) {
      return PaymentResult(
        status: PaymentResultStatus.error,
        message: 'Не удалось запустить покупку: $e',
      );
    } finally {
      await sub.cancel();
    }
  }

  bool _isStoreKitNoResponseError(PlatformException e) {
    final code = (e.code).toLowerCase();
    final blob = '${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
    return code.contains('storekit') ||
        code.contains('platform') ||
        blob.contains('failed to get response from platform');
  }

  ProductDetails? _productDetailsById(String storeProductId) {
    for (final p in _products) {
      if (p.id == storeProductId) return p;
    }
    return null;
  }

  bool _storeKitUseNonConsumable(String storeProductId) {
    if (_qarmetCatalog[storeProductId]?.isSubscription ?? false) {
      return true;
    }
    return storeProductId == premiumSubscriptionProductId ||
        storeProductId == profileCosmeticsLifetimeProductId;
  }

  Future<bool> _startPurchaseWithRetry({
    required ProductDetails product,
    required bool nonConsumable,
    required String storeProductId,
  }) async {
    Future<bool> startBuy(ProductDetails p) async {
      final param = PurchaseParam(productDetails: p);
      return nonConsumable
          ? _iap.buyNonConsumable(purchaseParam: param)
          : _iap.buyConsumable(purchaseParam: param, autoConsume: true);
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 520));
        await initStore();
      } else if (attempt == 2) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await initStore();
      }

      final details = attempt == 0
          ? product
          : _productDetailsById(storeProductId);
      if (details == null) {
        continue;
      }

      try {
        final ok = await startBuy(details);
        if (ok) return true;
      } on PlatformException catch (e) {
        if (!_isStoreKitNoResponseError(e)) rethrow;
      }
    }
    return false;
  }

  /// Убираем сырой текст «StoreKit: Failed to get response…» из UI.
  String _friendlyIapUserMessage(String? raw) {
    if (raw == null || raw.isEmpty) return 'Ошибка покупки';
    final lower = raw.toLowerCase();
    if (lower.contains('failed to get response from platform') ||
        lower.contains('storekit')) {
      return 'Не удалось связаться с App Store. Подождите несколько секунд, '
          'закройте и снова откройте экран оплаты. Для теста нужен Sandbox Apple ID '
          'и включённые In-App Purchase для приложения.';
    }
    return raw;
  }

  String _friendlyStoreError(PlatformException e) {
    return _friendlyIapUserMessage(
      '${e.code} ${e.message ?? ''} ${e.details ?? ''}',
    );
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

  Future<void> _creditQarmet(
    int amount, {
    required String reason,
    int? baseAmount,
    int? bonusAmount,
  }) async {
    final next = await _client.rpc<int>(
      'credit_qarmet',
      params: <String, dynamic>{
        'p_amount': amount,
        'p_reason': reason,
      },
    );
    debugPrint(
      'Qarmet credited: +$amount (base=${baseAmount ?? amount}, bonus=${bonusAmount ?? 0}) reason=$reason balance=$next',
    );
  }

  Future<void> _activatePromotionAtomic({
    required String productId,
    required String kind,
    required int cost,
    required int durationHours,
  }) async {
    try {
      await _client.rpc<void>(
        'spend_qarmet_and_apply_product_promotion',
        params: <String, dynamic>{
          'p_product_id': productId,
          'p_kind': kind,
          'p_cost': cost,
          'p_duration_hours': durationHours,
        },
      );
    } on PostgrestException catch (e) {
      throw Exception(e.message.isNotEmpty ? e.message : 'Не удалось применить продвижение');
    }
  }

  Future<void> _spendQarmet(int amount, {required String reason}) async {
    if (amount <= 0) {
      throw Exception('Сумма списания должна быть больше 0');
    }
    try {
      final next = await _client.rpc<int>(
        'spend_qarmet',
        params: <String, dynamic>{
          'p_amount': amount,
          'p_reason': reason,
        },
      );
      debugPrint('Qarmet spent: -$amount reason=$reason balance=$next');
    } on PostgrestException catch (e) {
      final normalized = e.message.trim().toLowerCase();
      if (normalized.contains('insufficient_qarmet')) {
        throw Exception('Недостаточно Qarmet для списания');
      }
      throw Exception(
        e.message.isNotEmpty ? e.message : 'Не удалось списать Qarmet',
      );
    }
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
    if (business.totalQarmet <= premium.totalQarmet) {
      throw StateError('Qarmet mapping invalid: business must exceed premium');
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
