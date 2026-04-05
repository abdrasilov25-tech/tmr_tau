import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/src/store_kit_2_wrappers/sk2_transaction_wrapper.dart'; // ignore: implementation_imports
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
  static const String promotionEliteProductId = 'qarmet_40';

  /// Единственный Product ID авто-подписки Official Page (ASC, Sandbox, StoreKit config).
  /// Дубликатов и legacy ID для этой подписки нет.
  static const String monthlySubscriptionProductId =
      'com.example.tmrTau.subscription.monthly';

  /// Алиас к [monthlySubscriptionProductId] (совместимость с остальным кодом).
  static const String officialPageProductId = monthlySubscriptionProductId;
  static const String premiumSubscriptionProductId = 'premium_subscription';
  static const String promotePostProductId = 'promote_post';
  /// Non-consumable: оформление профиля (рамки, бейджи, галочка) + стикеры на карте.
  static const String profileCosmeticsLifetimeProductId =
      'com.example.tmrTau.premium';

  /// Уровни, выставляемые на сервере при успешной покупке [profileCosmeticsLifetimeProductId].
  static const int profileCosmeticsIapMaxFrameLevel = 3;
  static const int profileCosmeticsIapMaxBadgeLevel = 3;

  final SupabaseClient _client;
  final InAppPurchase _iap;

  List<ProductDetails> _products = const <ProductDetails>[];
  bool _storeAvailable = false;
  String? _storeInitError;
  bool _storeCatalogLoaded = false;

  /// Параллельные [initStore] (несколько Cubit’ов / экранов) ломают StoreKit 2:
  /// одновременные [queryProductDetails] часто дают пустой ответ.
  Future<void>? _initStoreFuture;

  /// Сброс кэша баланса при смене аккаунта (каталог IAP общий, не трогаем).
  void clearWalletMemoryCache() {
    _walletCache = null;
    _officialPageMonthlyRpcSucceededKeys.clear();
  }
  WalletSnapshot? _walletCache;
  DateTime? _lastMonthlyCreditCheckAt;

  /// Успешные вызовы [callCreditBonus] по ключу транзакции IAP (без повторного RPC при redelivery).
  final Set<String> _officialPageMonthlyRpcSucceededKeys = <String>{};
  static const String _walletCachePrefix = 'qarmet_wallet_snapshot_v1_';
  static const String _premiumIapLocalPrefix = 'premium_iap_unlocked_v1_';

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
    // LIVE-battle mapping: qarmet_40 -> 800.
    promotionEliteProductId: QarmetProduct(
      productId: promotionEliteProductId,
      title: 'Elite',
      baseQarmet: 800,
      bonusQarmet: 0,
      priceKzt: 2499,
    ),
    // Месячная подписка Official Page (Store); ежемесячные Qarmet — RPC credit_official_page_monthly_qarmet.
    monthlySubscriptionProductId: QarmetProduct(
      productId: monthlySubscriptionProductId,
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

  /// true только когда [initStore] успешно завершился и продукты загружены.
  bool get isStoreCatalogLoaded => _storeCatalogLoaded && _storeAvailable;

  /// Плагин iOS отдаёт [IAPError] `storekit_no_response`, если нативный ответ пустой
  /// (часто гонка сразу после cold start, не «нет сети»).
  bool _isTransientStoreKitQueryError(IAPError? e) {
    if (e == null) return false;
    final code = e.code.toLowerCase();
    final msg = e.message.toLowerCase();
    return code == 'storekit_no_response' ||
        msg.contains('failed to get response from platform');
  }

  void _logProductQueryResult(
    String tag,
    ProductDetailsResponse response,
    Set<String> requestedIds,
  ) {
    final found = response.productDetails.map((p) => p.id).toList()..sort();
    final nf = List<String>.from(response.notFoundIDs)..sort();
    final err = response.error;
    debugPrint(
      'IAP[$tag] requested=${requestedIds.length} [${requestedIds.join(",")}] '
      '-> found=${found.length} [$found] notFound=[$nf] '
      'error=${err?.code ?? "-"} ${err?.message ?? ""}',
    );
    for (final p in response.productDetails) {
      debugPrint('IAP[$tag]   id=${p.id} title=${p.title} price=${p.price}');
    }
    if (err != null && response.productDetails.isNotEmpty) {
      debugPrint(
        'IAP[$tag] warning: IAPError present while productDetails non-empty',
      );
    }
  }

  Future<ProductDetailsResponse> _queryProductDetailsOnceWithTransientRetries(
    Set<String> productIds,
  ) async {
    var response = await _iap.queryProductDetails(productIds);
    const maxRetries = 3;
    for (var i = 0;
        i < maxRetries &&
            response.error != null &&
            _isTransientStoreKitQueryError(response.error);
        i++) {
      final ms = 300 * (i + 1);
      debugPrint(
        'IAP queryProductDetails transient error (${response.error!.code}), '
        'retry in ${ms}ms (${i + 1}/$maxRetries)',
      );
      await Future<void>.delayed(Duration(milliseconds: ms));
      response = await _iap.queryProductDetails(productIds);
    }
    return response;
  }

  Future<ProductDetailsResponse> _queryProductDetailsWithRetry(
    Set<String> productIds,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 60));
    var response = await _queryProductDetailsOnceWithTransientRetries(productIds);
    // Пустой список при отсутствии жёсткой ошибки — типично для симулятора / гонки после старта.
    if (productIds.isNotEmpty && response.productDetails.isEmpty) {
      const emptyMax = 5;
      for (var j = 0; j < emptyMax; j++) {
        if (response.productDetails.isNotEmpty) break;
        if (response.error != null &&
            !_isTransientStoreKitQueryError(response.error)) {
          break;
        }
        final ms = 280 * (j + 1);
        debugPrint(
          'IAP queryProductDetails empty (err=${response.error?.code}), '
          'retry in ${ms}ms (${j + 1}/$emptyMax)',
        );
        await Future<void>.delayed(Duration(milliseconds: ms));
        response = await _queryProductDetailsOnceWithTransientRetries(productIds);
      }
    }
    _logProductQueryResult('queryProductDetails', response, productIds);
    return response;
  }

  void _mergeProductDetailsIntoCache(Iterable<ProductDetails> incoming) {
    final byId = <String, ProductDetails>{
      for (final p in _products) p.id: p,
    };
    for (final p in incoming) {
      byId[p.id] = p;
    }
    _products = byId.values.toList(growable: false);
  }

  /// Целевой запрос подписки Official Page, если её не было в общем каталоге.
  Future<bool> _ensureMonthlySubscriptionProductDetails() async {
    if (_productDetailsById(monthlySubscriptionProductId) != null) {
      return true;
    }
    if (!_storeAvailable) return false;
    debugPrint(
      'IAP: targeted query for monthly subscription '
      '($monthlySubscriptionProductId)',
    );
    final r = await _queryProductDetailsWithRetry({monthlySubscriptionProductId});
    if (r.productDetails.isEmpty) {
      if (r.error != null) {
        debugPrint(
          'IAP targeted subscription: empty products, error=${r.error}',
        );
      }
      return false;
    }
    _mergeProductDetailsIntoCache(r.productDetails);
    return _productDetailsById(monthlySubscriptionProductId) != null;
  }

  /// StoreKit 2 иногда возвращает пустой список на большой [queryProductDetails] —
  /// порционные запросы обходят это при локальном .storekit и на симуляторе.
  Future<ProductDetailsResponse> _queryProductDetailsInChunks(
    Set<String> productIds, {
    int chunkSize = 4,
  }) async {
    final list = productIds.toList()..sort();
    final merged = <ProductDetails>[];
    IAPError? firstHardError;

    for (var i = 0; i < list.length; i += chunkSize) {
      final end = i + chunkSize > list.length ? list.length : i + chunkSize;
      final chunk = list.sublist(i, end).toSet();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final r = await _queryProductDetailsWithRetry(chunk);
      if (r.error != null && r.productDetails.isEmpty && firstHardError == null) {
        firstHardError = r.error;
      }
      merged.addAll(r.productDetails);
    }

    final found = merged.map((e) => e.id).toSet();
    final missing = productIds.where((id) => !found.contains(id)).toList();

    return ProductDetailsResponse(
      productDetails: merged,
      notFoundIDs: missing,
      error: merged.isEmpty ? firstHardError : null,
    );
  }

  /// Последний fallback: по одному ID (с ретраями на каждый).
  Future<ProductDetailsResponse> _queryProductDetailsSequentialIds(
    Set<String> productIds,
  ) async {
    final merged = <ProductDetails>[];
    IAPError? lastErr;
    final sorted = productIds.toList()..sort();
    for (final id in sorted) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final r = await _queryProductDetailsWithRetry({id});
      if (r.error != null && r.productDetails.isEmpty && lastErr == null) {
        lastErr = r.error;
      }
      merged.addAll(r.productDetails);
    }
    final found = merged.map((e) => e.id).toSet();
    final missing = productIds.where((id) => !found.contains(id)).toList();
    return ProductDetailsResponse(
      productDetails: merged,
      notFoundIDs: missing,
      error: merged.isEmpty ? lastErr : null,
    );
  }

  Future<void> _warmUpStoreKitProductQuery() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    try {
      // Minimal delay — just enough to let the StoreKit channel initialise after cold start.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _iap.queryProductDetails({promotionStartProductId});
    } catch (e, st) {
      debugPrint('IAP warm-up query ignored: $e\n$st');
    }
  }

  Future<void> initStore({bool forceCatalogRefresh = false}) {
    if (!forceCatalogRefresh &&
        _storeCatalogLoaded &&
        _products.isNotEmpty &&
        _storeAvailable) {
      return Future<void>.value();
    }
    final existing = _initStoreFuture;
    if (existing != null) return existing;
    _initStoreFuture =
        _initStoreOnce(forceCatalogRefresh: forceCatalogRefresh).whenComplete(() {
      _initStoreFuture = null;
    });
    return _initStoreFuture!;
  }

  Future<void> _initStoreOnce({required bool forceCatalogRefresh}) async {
    if (!forceCatalogRefresh &&
        _storeCatalogLoaded &&
        _products.isNotEmpty &&
        _storeAvailable) {
      return;
    }
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final available = await _iap.isAvailable();
      _storeAvailable = available;
      if (!available) {
        _products = const <ProductDetails>[];
        _storeCatalogLoaded = false;
        _storeInitError = 'Магазин покупок недоступен на устройстве';
        debugPrint('IAP init: store unavailable');
        return;
      }

      final allIds = {..._qarmetCatalog.keys, ..._extraIapProductIds};

      await _warmUpStoreKitProductQuery();

      var response = await _queryProductDetailsWithRetry(allIds);
      if (response.productDetails.isEmpty && allIds.length > 1) {
        debugPrint(
          'IAP init: пустой список продуктов (error=${response.error?.code}), '
          'пробуем порционный queryProductDetails',
        );
        response = await _queryProductDetailsInChunks(allIds);
      }
      if (response.productDetails.isEmpty && allIds.isNotEmpty) {
        debugPrint(
          'IAP init: порционный запрос без продуктов, пробуем по одному Product ID',
        );
        response = await _queryProductDetailsSequentialIds(allIds);
      }

      if (response.productDetails.isEmpty) {
        _products = const <ProductDetails>[];
        _storeCatalogLoaded = false;
        if (response.error != null) {
          _storeInitError =
              _friendlyIapUserMessage(response.error!.message);
          debugPrint('IAP init queryProductDetails error: ${response.error}');
        } else {
          _storeInitError =
              'Не удалось получить товары из App Store. Проверьте StoreKit Configuration '
              'в схеме Xcode и Product ID в App Store Connect.';
        }
        return;
      }

      _products = response.productDetails;
      _storeCatalogLoaded = true;
      debugPrint(
        'IAP catalog loaded: count=${_products.length} '
        'ids=[${_products.map((e) => e.id).join(",")}]',
      );
      if (_productDetailsById(monthlySubscriptionProductId) == null &&
          _products.isNotEmpty) {
        debugPrint(
          'IAP init: monthly subscription missing from batch; targeted query',
        );
        final subR =
            await _queryProductDetailsWithRetry({monthlySubscriptionProductId});
        _logProductQueryResult('init-monthly-topup', subR, {
          monthlySubscriptionProductId,
        });
        if (subR.productDetails.isNotEmpty) {
          _mergeProductDetailsIntoCache(subR.productDetails);
        }
      }
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
      _storeCatalogLoaded = false;
      // Не ставим _storeAvailable = false: сбой запроса каталога ≠ «магазин недоступен
      // на устройстве». Иначе после временной ошибки StoreKit/Play Billing экран
      // остаётся «мёртвым» до полного перезапуска приложения.
      try {
        _storeAvailable = await _iap.isAvailable();
      } catch (_) {
        _storeAvailable = false;
      }
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
        if (package.isSubscription) {
          await _creditOfficialPageMonthlyAfterSubscriptionPurchase(purchase);
        }
        await _creditPurchasedQarmet(package);
      },
    );
  }

  Future<void> restorePurchases() async {
    final auth = _client.auth.currentUser;
    if (auth == null) {
      await _iap.restorePurchases();
      return;
    }

    final completer = Completer<void>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = _iap.purchaseStream.listen(
      (purchases) async {
        for (final purchase in purchases) {
          debugPrint(
            'IAP restore stream: product=${purchase.productID} '
            'status=${purchase.status.name} pendingComplete='
            '${purchase.pendingCompletePurchase} error=${purchase.error}',
          );
          if (purchase.productID != profileCosmeticsLifetimeProductId) {
            continue;
          }
          if (purchase.status == PurchaseStatus.pending) {
            debugPrint('IAP restore: pending (cosmetics)');
            continue;
          }
          if (purchase.status == PurchaseStatus.error) {
            final err = purchase.error;
            debugPrint(
              'IAP restore: error code=${err?.code} message=${err?.message}',
            );
            continue;
          }
          if (purchase.status != PurchaseStatus.purchased &&
              purchase.status != PurchaseStatus.restored) {
            continue;
          }
          try {
            await _verifyPurchase(purchase, profileCosmeticsLifetimeProductId);
            await _setPremiumIapLocalUnlocked(true, userId: auth.id);
            await _completeIapPurchase(purchase);
          } catch (e, st) {
            debugPrint('IAP restore processing error: $e\n$st');
          }
        }
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (e, st) {
        debugPrint('IAP restore stream error: $e\n$st');
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    try {
      await _iap.restorePurchases();
      await completer.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () {},
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Premium для ленты «Рядом» (радиусы 10/20 км): только IAP `premium_subscription`
  /// в полях [premium_active] / [premium_until]. Подписка продавца [official_page_active] сюда не входит.
  Future<({bool active, DateTime? until})> getNewsMapPremiumInfo() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return (active: false, until: null);
    try {
      final row = await _client
          .from('users')
          .select('premium_active,premium_until')
          .eq('id', auth.id)
          .maybeSingle();
      if (row == null) return (active: false, until: null);
      final flag = row['premium_active'] as bool? ?? false;
      final untilRaw = row['premium_until'] as String?;
      final until = DateTime.tryParse(untilRaw ?? '')?.toUtc();
      final now = DateTime.now().toUtc();
      final byDate = until != null && until.isAfter(now);
      return (active: flag || byDate, until: until);
    } catch (_) {
      return (active: false, until: null);
    }
  }

  Future<bool> isPremiumActive() async {
    final r = await getNewsMapPremiumInfo();
    return r.active;
  }

  /// Цена из App Store / StoreKit Configuration (после [initStore]).
  String? storeKitPriceForProduct(String storeProductId) {
    return _productDetailsById(storeProductId)?.price;
  }

  /// Название товара из магазина (после [initStore]).
  String? storeKitTitleForProduct(String storeProductId) {
    return _productDetailsById(storeProductId)?.title;
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
        final auth = _requireAuthUser();
        await _setPremiumIapLocalUnlocked(true, userId: auth.id);
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
    final localUnlocked = await _getPremiumIapLocalUnlocked(userId: auth.id);
    if (localUnlocked) return true;
    final row = await _client
        .from('users')
        .select('profile_cosmetics_iap_forever')
        .eq('id', auth.id)
        .maybeSingle();
    final serverUnlocked = row?['profile_cosmetics_iap_forever'] as bool? ?? false;
    if (serverUnlocked) {
      await _setPremiumIapLocalUnlocked(true, userId: auth.id);
    }
    return serverUnlocked;
  }

  Future<void> ensureMonthlySubscriptionCredit() async {
    final now = DateTime.now().toUtc();
    final lastCheck = _lastMonthlyCreditCheckAt;
    if (lastCheck != null && now.difference(lastCheck) < const Duration(minutes: 10)) {
      return;
    }
    _lastMonthlyCreditCheckAt = now;

    if (_client.auth.currentUser == null) return;
    await callCreditBonus();
  }

  /// Supabase RPC `credit_official_page_monthly_qarmet` — ежемесячное начисление при активной official_page.
  /// Не бросает: ошибки только в логах. Возвращает новый баланс или `null` при сбое / неавторизован.
  Future<int?> callCreditBonus() async {
    debugPrint('Qarmet RPC: callCreditBonus → credit_official_page_monthly_qarmet');
    final auth = _client.auth.currentUser;
    if (auth == null) {
      debugPrint('Qarmet RPC: callCreditBonus aborted (not signed in)');
      return null;
    }
    try {
      final raw = await _client.rpc<dynamic>('credit_official_page_monthly_qarmet');
      debugPrint('Qarmet RPC: callCreditBonus raw response: $raw');
      final balance = raw is int
          ? raw
          : (raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? ''));
      if (balance == null) {
        debugPrint('Qarmet RPC: callCreditBonus unexpected null/non-int response');
        _walletCache = null;
        return null;
      }
      debugPrint('Qarmet RPC: callCreditBonus success balance=$balance user=${auth.id}');
      _walletCache = null;
      return balance;
    } on PostgrestException catch (e, st) {
      debugPrint(
        'Qarmet RPC: callCreditBonus PostgrestException code=${e.code} '
        'message=${e.message}\n$st',
      );
      return null;
    } catch (e, st) {
      debugPrint('Qarmet RPC: callCreditBonus error $e\n$st');
      return null;
    }
  }

  String _officialPagePurchaseDedupeKey(PurchaseDetails p) {
    final pid = (p.purchaseID ?? '').trim();
    if (pid.isNotEmpty) {
      return '${p.productID}|$pid';
    }
    final blob = p.verificationData.serverVerificationData.trim();
    if (blob.isNotEmpty) {
      return '${p.productID}|h${blob.hashCode}';
    }
    return '${p.productID}|t${p.transactionDate ?? ""}';
  }

  /// Один успешный RPC на успешную покупку/restore подписки Official Page (без повторов при redelivery StoreKit).
  Future<void> _creditOfficialPageMonthlyAfterSubscriptionPurchase(
    PurchaseDetails purchase,
  ) async {
    debugPrint(
      'IAP official_page subscription: purchase received '
      'status=${purchase.status.name} id=${purchase.productID}',
    );
    final key = _officialPagePurchaseDedupeKey(purchase);
    if (_officialPageMonthlyRpcSucceededKeys.contains(key)) {
      debugPrint(
        'Qarmet RPC: skip credit_official_page_monthly_qarmet (already succeeded) key=$key',
      );
      return;
    }
    final balance = await callCreditBonus();
    if (balance != null) {
      if (_officialPageMonthlyRpcSucceededKeys.length >= 64) {
        _officialPageMonthlyRpcSucceededKeys.clear();
      }
      _officialPageMonthlyRpcSucceededKeys.add(key);
      debugPrint(
        'Qarmet RPC: official_page purchase chain recorded success key=$key',
      );
    } else {
      debugPrint(
        'Qarmet RPC: official_page purchase chain RPC did not succeed; key not pinned (may retry)',
      );
    }
  }

  WalletSnapshot? getCachedWalletSnapshot({
    Duration maxAge = const Duration(minutes: 8),
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
    if (_client.auth.currentUser == null) {
      final snap = WalletSnapshot(
        balance: 0,
        isOfficialPageActive: false,
        cosmeticsLifetimeUnlocked: false,
        promotionHistory: const [],
        catalog: catalog,
        fetchedAt: DateTime.now().toUtc(),
      );
      _walletCache = snap;
      return snap;
    }
    if (!forceRefresh) {
      final cached = getCachedWalletSnapshot();
      if (cached != null) return cached;
      final disk = await getPersistentWalletSnapshot();
      if (disk != null) {
        _walletCache = disk;
        return disk;
      }
    }
    // Kick off monthly credit check in background — don't block wallet load.
    unawaited(ensureMonthlySubscriptionCredit());

    final results = await Future.wait<Object>([
      _getUserWalletFields(),
      getMyPromotionHistory().catchError(
        (_) => const <QarmetPromotionHistoryItem>[],
      ),
    ]);
    final fields = results[0] as _UserWalletFields;
    // Sync cosmetics local flag if server says unlocked (background, non-blocking).
    if (fields.cosmeticsUnlocked) {
      final auth = _client.auth.currentUser;
      if (auth != null) unawaited(_setPremiumIapLocalUnlocked(true, userId: auth.id));
    }
    final snapshot = WalletSnapshot(
      balance: fields.balance,
      isOfficialPageActive: fields.officialPageActive,
      cosmeticsLifetimeUnlocked: fields.cosmeticsUnlocked,
      promotionHistory: results[1] as List<QarmetPromotionHistoryItem>,
      catalog: catalog,
      fetchedAt: DateTime.now().toUtc(),
    );
    _walletCache = snapshot;
    unawaited(_savePersistentWalletSnapshot(snapshot));
    return snapshot;
  }

  /// Single DB round-trip replacing getQarmetBalance + isOfficialPageActive + getCosmeticsLifetimeUnlocked.
  Future<_UserWalletFields> _getUserWalletFields() async {
    final auth = _client.auth.currentUser;
    if (auth == null) return const _UserWalletFields();
    try {
      // Check local flag first (avoids DB call if already confirmed locally).
      final localUnlocked = await _getPremiumIapLocalUnlocked(userId: auth.id);
      final row = await _client
          .from('users')
          .select('qarmet_balance, official_page_active, profile_cosmetics_iap_forever')
          .eq('id', auth.id)
          .maybeSingle();
      if (row == null) return _UserWalletFields(cosmeticsUnlocked: localUnlocked);
      final serverCosmetics = row['profile_cosmetics_iap_forever'] as bool? ?? false;
      return _UserWalletFields(
        balance: row['qarmet_balance'] as int? ?? 0,
        officialPageActive: row['official_page_active'] as bool? ?? false,
        cosmeticsUnlocked: localUnlocked || serverCosmetics,
      );
    } catch (_) {
      return const _UserWalletFields();
    }
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
        .order('created_at', ascending: false)
        .limit(50);
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

  /// Spend Qarmet to purchase a chat pet.
  Future<void> spendForChatPet({required int cost, required String petId}) async {
    _requireAuthUser();
    if (cost <= 0) return; // free pet — no spend needed
    await _spendQarmet(cost, reason: 'chat_pet_$petId');
  }

  /// StoreKit 2: [InAppPurchase.completePurchase] делает `int.parse(purchase.purchaseID!)`.
  /// Если [PurchaseDetails.purchaseID] null (краевые случаи в плагине), приложение падает
  /// с «Null check operator used on a null value». Здесь — безопасное завершение + fallback.
  Future<void> _completeIapPurchase(PurchaseDetails purchase) async {
    if (!purchase.pendingCompletePurchase) return;

    final pid = purchase.purchaseID;
    if (pid != null && pid.isNotEmpty) {
      await _iap.completePurchase(purchase);
      return;
    }

    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }

    final finishId = _tryExtractSk2FinishTransactionId(purchase);
    if (finishId != null && finishId > 0) {
      try {
        await SK2Transaction.finish(finishId);
        return;
      } catch (e, st) {
        debugPrint('IAP SK2Transaction.finish fallback failed: $e\n$st');
      }
    }

    debugPrint(
      'IAP: cannot finish transaction — missing purchaseID; '
      'product=${purchase.productID} platform=${defaultTargetPlatform.name}',
    );
  }

  /// Пытается извлечь целочисленный id транзакции SK2 для [SK2Transaction.finish].
  int? _tryExtractSk2FinishTransactionId(PurchaseDetails purchase) {
    int? fromJsonValue(Object? raw) {
      if (raw is int) return raw;
      if (raw is num) return raw.toInt();
      if (raw is String) return int.tryParse(raw);
      return null;
    }

    int? fromMap(Map<String, dynamic> m) {
      const keys = <String>[
        'transactionId',
        'originalTransactionId',
        'transaction_id',
        'original_transaction_id',
      ];
      for (final k in keys) {
        final v = fromJsonValue(m[k]);
        if (v != null && v > 0) return v;
      }
      return null;
    }

    int? tryDecodeJsonObject(String source) {
      if (source.isEmpty) return null;
      try {
        final decoded = jsonDecode(source);
        if (decoded is Map) {
          return fromMap(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
      return null;
    }

    int? tryDecodeJwsPayload(String jws) {
      final parts = jws.split('.');
      if (parts.length < 2) return null;
      try {
        var payload = parts[1];
        final pad = payload.length % 4;
        if (pad == 2) {
          payload += '==';
        } else if (pad == 3) {
          payload += '=';
        }
        final bytes = base64Url.decode(payload);
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is Map) {
          return fromMap(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
      return null;
    }

    return tryDecodeJsonObject(purchase.verificationData.localVerificationData) ??
        tryDecodeJwsPayload(purchase.verificationData.serverVerificationData);
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
    final acceptedStoreIds = <String>{storeProductId};
    ProductDetails? product;
    for (final p in _products) {
      if (acceptedStoreIds.contains(p.id)) {
        product = p;
        break;
      }
    }
    if (product == null && storeProductId == monthlySubscriptionProductId) {
      final ok = await _ensureMonthlySubscriptionProductDetails();
      if (ok) {
        product = _productDetailsById(storeProductId);
      }
    }
    if (product == null) {
      debugPrint(
        'IAP _purchase: product not in cache storeProductId=$storeProductId '
        'cachedIds=[${_products.map((e) => e.id).join(",")}]',
      );
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
          if (!acceptedStoreIds.contains(purchase.productID)) continue;

          debugPrint(
            'IAP purchase stream: id=${purchase.productID} '
            'status=${purchase.status.name} '
            'pendingComplete=${purchase.pendingCompletePurchase} '
            'error=${purchase.error}',
          );

          try {
            switch (purchase.status) {
              case PurchaseStatus.pending:
                debugPrint('IAP purchase stream: pending (awaiting StoreKit)');
                break;
              case PurchaseStatus.purchased:
              case PurchaseStatus.restored:
                debugPrint(
                  'IAP purchase stream: ${purchase.status.name} -> verify',
                );
                await onVerified(purchase);
                await _completeIapPurchase(purchase);
                if (!completer.isCompleted) {
                  completer.complete(
                    const PaymentResult(status: PaymentResultStatus.success),
                  );
                }
                break;
              case PurchaseStatus.canceled:
                debugPrint('IAP purchase stream: canceled');
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
                final iapErr = purchase.error;
                debugPrint(
                  'IAP purchase stream: error code=${iapErr?.code} '
                  'message=${iapErr?.message} details=${iapErr?.details}',
                );
                if (!completer.isCompleted) {
                  completer.complete(
                    PaymentResult(
                      status: PaymentResultStatus.error,
                      message: _friendlyIapUserMessage(iapErr?.message),
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
                  message: _friendlyPurchaseProcessingError(e),
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
        storeProductIds: acceptedStoreIds,
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
    final blob = '${e.message ?? ''} ${e.details ?? ''}'.toLowerCase();
    // Только известный сбой platform channel; code часто содержит "storekit2_*" при обычных IAP-ошибках.
    return blob.contains('failed to get response from platform');
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
    required Set<String> storeProductIds,
  }) async {
    Future<bool> startBuy(ProductDetails p) async {
      final param = PurchaseParam(productDetails: p);
      return nonConsumable
          ? _iap.buyNonConsumable(purchaseParam: param)
          : _iap.buyConsumable(purchaseParam: param, autoConsume: true);
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt == 1) {
        await Future<void>.delayed(const Duration(milliseconds: 280));
        await initStore(forceCatalogRefresh: true);
      } else if (attempt == 2) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        await initStore(forceCatalogRefresh: true);
      }

      final details = attempt == 0
          ? product
          : _productFromAcceptedIds(storeProductIds);
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

  ProductDetails? _productFromAcceptedIds(Set<String> storeProductIds) {
    for (final id in storeProductIds) {
      final details = _productDetailsById(id);
      if (details != null) return details;
    }
    return null;
  }

  /// Сообщение для пользователя; не подменяем любую ошибку со словом «storekit» —
  /// при StoreKit Testing в тексте почти всегда есть storekit/storekit2, иначе UI врёт про «App Store».
  String _friendlyIapUserMessage(String? raw) {
    if (raw == null || raw.isEmpty) return 'Ошибка покупки';
    final lower = raw.toLowerCase();
    if (lower.contains('failed to get response from platform')) {
      return 'Не удалось получить ответ от StoreKit. Подождите несколько секунд, '
          'закройте экран оплаты и откройте снова или перезапустите приложение. '
          'При тесте через Xcode: Run → Options → StoreKit Configuration = storekit.storekit. '
          'На устройстве без этого файла нужен Sandbox Apple ID и товары в App Store Connect.';
    }
    // Не подменяем любой «401 + FunctionException» — это даёт ложное «сессия устарела»
    // при 401 от getUser() на Edge (секреты/проект) или No Authorization.
    if (lower.contains('invalid jwt')) {
      return 'Сессия устарела для проверки покупки на сервере. Выйдите из аккаунта '
          'и войдите снова, затем повторите покупку. Если ошибка остаётся — проверьте, '
          'что в .env указан тот же проект Supabase, что и у задеплоенной функции verifyPurchase.';
    }
    return raw;
  }

  /// Человекочитаемый текст для сбоев после успешного ответа StoreKit (verifyPurchase / RPC).
  String _friendlyPurchaseProcessingError(Object error) {
    if (error is FunctionException) {
      return _friendlyVerifyPurchaseFunctionException(error);
    }
    return _friendlyIapUserMessage(error.toString());
  }

  String _friendlyVerifyPurchaseFunctionException(FunctionException e) {
    final details = e.details;
    final Map<String, dynamic>? detailsMap = details is Map
        ? Map<String, dynamic>.from(details)
        : null;
    final code = detailsMap?['error_code']?.toString();

    if (e.status == 403 && code == 'user_id_mismatch') {
      return 'Аккаунт в приложении не совпадает с покупкой. Войдите в тот профиль, '
          'с которого оформляли подписку, и повторите.';
    }
    if (e.status == 401) {
      if (code == 'no_authorization_header') {
        return 'Запрос к серверу без токена авторизации. Перезапустите приложение и войдите снова.';
      }
      if (code == 'auth_get_user_failed') {
        final hint = detailsMap?['auth_message']?.toString();
        final tail = (hint != null && hint.isNotEmpty) ? ' ($hint)' : '';
        return 'Сервер не смог подтвердить вход при проверке покупки$tail. '
            'Выйдите из аккаунта и войдите снова. Если не помогает — в Supabase Dashboard '
            'проверьте секреты Edge Function verifyPurchase (SUPABASE_URL и ANON_KEY того же проекта, '
            'что в приложении), затем выполните: supabase functions deploy verifyPurchase';
      }
      final raw = details?.toString().toLowerCase() ?? '';
      if (raw.contains('invalid jwt')) {
        return _friendlyIapUserMessage('Invalid JWT');
      }
      return 'Покупку не удалось подтвердить на сервере (ошибка авторизации). '
          'Войдите снова; если повторяется — проверьте совпадение проекта Supabase в .env и деплой verifyPurchase.';
    }
    if (e.status == 400 && detailsMap?['error'] != null) {
      return 'Проверка покупки: ${detailsMap!['error']}';
    }
    return _friendlyIapUserMessage(
      'FunctionException(status: ${e.status}, details: $details, reasonPhrase: ${e.reasonPhrase})',
    );
  }

  String _friendlyStoreError(PlatformException e) {
    final code = e.code.toLowerCase();
    if (code.contains('failed_to_fetch_product') ||
        code == 'storekit2_products_error') {
      return 'Товар не найден в StoreKit. Сверьте Product ID с ios/storekit.storekit и '
          'PaymentService; в схеме Runner должен быть подключён StoreKit Configuration.';
    }
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

  /// JWS транзакции (предпочтительно) или JSON StoreKit 2: при тесте через
  /// StoreKit Configuration иногда пустой [PurchaseVerificationData.serverVerificationData],
  /// из‑за чего Edge Function отвечает 400 «Invalid purchase payload».
  String _purchaseVerificationPayloadForVerify(PurchaseDetails purchase) {
    final v = purchase.verificationData;
    final server = v.serverVerificationData.trim();
    if (server.isNotEmpty) return server;
    return v.localVerificationData.trim();
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
    if (_client.auth.currentSession == null) {
      throw Exception('Пользователь не авторизован');
    }

    final verificationPayload = _purchaseVerificationPayloadForVerify(purchase);
    if (verificationPayload.isEmpty) {
      throw Exception(
        'Нет данных чека StoreKit (пустой JWS/JSON транзакции). '
        'В Xcode: схема Runner → Run → Options → StoreKit Configuration = storekit.storekit. '
        'Повторите покупку.',
      );
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      final refreshed = await _client.auth.refreshSession();
      final token =
          refreshed.session?.accessToken ?? _client.auth.currentSession?.accessToken;
      if (token == null || token.isEmpty) {
        throw Exception('Сессия истекла. Войдите снова и повторите покупку.');
      }

      // Тот же вызов, что использует Edge getUser(): если здесь ок — токен валиден для проекта.
      late final UserResponse validated;
      try {
        validated = await _client.auth.getUser();
      } on AuthException catch (e) {
        throw Exception(
          'Не удалось подтвердить сессию: ${e.message}. Выйдите и войдите снова.',
        );
      }
      if (validated.user == null || validated.user!.id != auth.id) {
        throw Exception(
          'Аккаунт не подтверждён после обновления сессии. Выйдите и войдите снова.',
        );
      }

      try {
        final response = await _client.functions.invoke(
          'verifyPurchase',
          headers: {'Authorization': 'Bearer $token'},
          body: <String, dynamic>{
            'userId': auth.id,
            'productId': productId,
            'purchaseId': purchase.purchaseID,
            'transactionDate': purchase.transactionDate,
            'verificationData': verificationPayload,
            'source': purchase.verificationData.source,
            'platform': defaultTargetPlatform.name,
          },
        );
        final data = response.data;
        if (data is Map && data['verified'] == true) return;
        final errMsg = data is Map
            ? (data['error']?.toString() ?? 'Сервер не подтвердил покупку')
            : 'Сервер не подтвердил покупку';
        throw Exception('verifyPurchase: $errMsg');
      } on FunctionException catch (e) {
        final retryable401 = e.status == 401 &&
            attempt < 2 &&
            _verifyPurchase401MayBeTransient(e);
        if (retryable401) {
          await Future<void>.delayed(Duration(milliseconds: 200 * (attempt + 1)));
          continue;
        }
        throw Exception(_friendlyVerifyPurchaseFunctionException(e));
      }
    }
  }

  /// Повторяем только типичные гонки/временные отказы шлюза, не «логические» 401.
  bool _verifyPurchase401MayBeTransient(FunctionException e) {
    final details = e.details;
    if (details is! Map) {
      return true;
    }
    final m = Map<String, dynamic>.from(details);
    final code = m['error_code']?.toString();
    if (code == 'user_id_mismatch') return false;
    if (code == 'auth_get_user_failed') return false;
    if (code == 'no_authorization_header') return false;
    return true;
  }

  Future<void> _setPremiumIapLocalUnlocked(
    bool unlocked, {
    required String userId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_premiumIapLocalPrefix$userId', unlocked);
    } catch (_) {
      // Non-critical cache path.
    }
  }

  Future<bool> _getPremiumIapLocalUnlocked({required String userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('$_premiumIapLocalPrefix$userId') ?? false;
    } catch (_) {
      return false;
    }
  }
}

class _UserWalletFields {
  const _UserWalletFields({
    this.balance = 0,
    this.officialPageActive = false,
    this.cosmeticsUnlocked = false,
  });
  final int balance;
  final bool officialPageActive;
  final bool cosmeticsUnlocked;
}
