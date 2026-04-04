import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/services/payment_service.dart';
import '../../domain/entities/qarmet_promotion_history_item.dart';
import '../../domain/entities/qarmet_product.dart';

enum PaymentUiStatus { idle, loading, success, error, cancelled }

class PaymentUiState {
  const PaymentUiState({
    this.status = PaymentUiStatus.idle,
    this.message,
    this.storeInitError,
    this.balance = 0,
    this.catalog = const <QarmetProduct>[],
    this.isOfficialPageActive = false,
    this.cosmeticsLifetimeUnlocked = false,
    this.promotionHistory = const <QarmetPromotionHistoryItem>[],
    this.purchasingQarmetProductId,
    this.isStoreReady = false,
  });

  final PaymentUiStatus status;
  final String? message;

  /// Ошибка инициализации StoreKit/IAP — не null когда магазин недоступен
  /// или товары не удалось загрузить.
  final String? storeInitError;

  final int balance;
  final List<QarmetProduct> catalog;
  final bool isOfficialPageActive;
  final bool cosmeticsLifetimeUnlocked;
  final List<QarmetPromotionHistoryItem> promotionHistory;

  /// true когда StoreKit успешно загрузил продукты и покупки доступны.
  final bool isStoreReady;

  /// Покупка пакета Qarmet из магазина (IAP). Пока идёт — блокируем только этот SKU,
  /// а не все кнопки при [status] == loading.
  final String? purchasingQarmetProductId;

  /// Полное обновление кошелька / init: глушим все действия с Qarmet.
  bool get isWalletWideBusy =>
      status == PaymentUiStatus.loading && purchasingQarmetProductId == null;

  /// Локальный снимок экономики (синхронизируется с `users.qarmet_balance` через [refreshWallet]).
  int get userBalance => balance;

  /// Подписка Official Page / премиум-витрина (`users.official_page_active`).
  bool get isPremium => isOfficialPageActive;

  /// Можно нажать «купить» для этого productId (остальные пакеты остаются активными).
  bool canTapBuyQarmetPackage(String productId) {
    if (!isStoreReady) return false;
    if (status != PaymentUiStatus.loading) return true;
    return purchasingQarmetProductId != null &&
        purchasingQarmetProductId != productId;
  }

  PaymentUiState copyWith({
    PaymentUiStatus? status,
    String? message,
    String? storeInitError,
    bool clearStoreInitError = false,
    int? balance,
    List<QarmetProduct>? catalog,
    bool? isOfficialPageActive,
    bool? cosmeticsLifetimeUnlocked,
    List<QarmetPromotionHistoryItem>? promotionHistory,
    String? purchasingQarmetProductId,
    bool clearPurchasingQarmetProductId = false,
    bool? isStoreReady,
  }) {
    return PaymentUiState(
      status: status ?? this.status,
      message: message,
      storeInitError: clearStoreInitError
          ? null
          : (storeInitError ?? this.storeInitError),
      balance: balance ?? this.balance,
      catalog: catalog ?? this.catalog,
      isOfficialPageActive: isOfficialPageActive ?? this.isOfficialPageActive,
      cosmeticsLifetimeUnlocked:
          cosmeticsLifetimeUnlocked ?? this.cosmeticsLifetimeUnlocked,
      promotionHistory: promotionHistory ?? this.promotionHistory,
      purchasingQarmetProductId: clearPurchasingQarmetProductId
          ? null
          : (purchasingQarmetProductId ?? this.purchasingQarmetProductId),
      isStoreReady: isStoreReady ?? this.isStoreReady,
    );
  }
}

class PaymentCubit extends Cubit<PaymentUiState> {
  PaymentCubit(this._service) : super(const PaymentUiState());

  final PaymentService _service;

  void resetForLogout() {
    _service.clearWalletMemoryCache();
    emit(const PaymentUiState());
  }

  Future<void> initStore() async {
    try {
      // 1) Каталог пакетов Qarmet задан в коде — показываем сразу, не ждём StoreKit/сеть.
      final mem = _service.getCachedWalletSnapshot();
      final disk = mem ?? await _service.getPersistentWalletSnapshot();
      final warm = mem ?? disk;
      emit(
        state.copyWith(
          status: PaymentUiStatus.idle,
          message: null,
          catalog: _service.catalog,
          balance: warm?.balance ?? 0,
          isOfficialPageActive: warm?.isOfficialPageActive ?? false,
          cosmeticsLifetimeUnlocked:
              warm?.cosmeticsLifetimeUnlocked ?? false,
          promotionHistory: warm?.promotionHistory ?? const [],
          storeInitError: _service.storeInitError,
          isStoreReady: _service.isStoreCatalogLoaded,
          clearStoreInitError: _service.isStoreCatalogLoaded,
        ),
      );

      // 2) StoreKit и актуальные данные кошелька — параллельно, чтобы не суммировать задержки.
      final walletFuture = _service.loadWalletSnapshot(forceRefresh: false);
      await _service.initStore();
      final snapshot = await walletFuture;

      final storeErr = _service.storeInitError;
      final storeReady = _service.isStoreCatalogLoaded;
      emit(
        state.copyWith(
          status: PaymentUiStatus.idle,
          message: null,
          storeInitError: storeErr,
          clearStoreInitError: storeReady,
          isStoreReady: storeReady,
          balance: snapshot.balance,
          catalog: snapshot.catalog,
          isOfficialPageActive: snapshot.isOfficialPageActive,
          cosmeticsLifetimeUnlocked: snapshot.cosmeticsLifetimeUnlocked,
          promotionHistory: snapshot.promotionHistory,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: PaymentUiStatus.error,
          message: e.toString(),
          catalog: _service.catalog,
        ),
      );
    }
  }

  /// Повторная попытка инициализации StoreKit (вызывается по кнопке Retry в UI).
  Future<void> retryInitStore() async {
    emit(
      state.copyWith(
        status: PaymentUiStatus.loading,
        message: null,
        clearStoreInitError: true,
        isStoreReady: false,
      ),
    );
    await _service.initStore(forceCatalogRefresh: true);
    final storeErr = _service.storeInitError;
    final storeReady = _service.isStoreCatalogLoaded;
    emit(
      state.copyWith(
        status: PaymentUiStatus.idle,
        catalog: _service.catalog,
        storeInitError: storeErr,
        clearStoreInitError: storeReady,
        isStoreReady: storeReady,
      ),
    );
    await refreshWallet(silent: true, forceRefresh: true);
  }

  Future<void> refreshWallet({
    bool silent = false,
    bool forceRefresh = false,
  }) async {
    try {
      if (!silent) {
        emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
      }
      final snapshot = await _service.loadWalletSnapshot(
        forceRefresh: forceRefresh,
      );
      final storeErr = _service.storeInitError;
      final storeReady = _service.isStoreCatalogLoaded;
      emit(
        state.copyWith(
          status: PaymentUiStatus.idle,
          message: null,
          storeInitError: storeErr,
          clearStoreInitError: storeReady,
          isStoreReady: storeReady,
          balance: snapshot.balance,
          catalog: snapshot.catalog,
          isOfficialPageActive: snapshot.isOfficialPageActive,
          cosmeticsLifetimeUnlocked: snapshot.cosmeticsLifetimeUnlocked,
          promotionHistory: snapshot.promotionHistory,
          clearPurchasingQarmetProductId: true,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: PaymentUiStatus.error,
          message: e.toString(),
          catalog: _service.catalog,
          clearPurchasingQarmetProductId: true,
        ),
      );
    }
  }

  Future<void> purchaseProfileCosmeticsLifetime() async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      final result = await _service.purchaseProfileCosmeticsLifetime();
      switch (result.status) {
        case PaymentResultStatus.success:
          await refreshWallet(silent: true, forceRefresh: true);
          emit(state.copyWith(status: PaymentUiStatus.success));
        case PaymentResultStatus.cancelled:
          emit(
            state.copyWith(
              status: PaymentUiStatus.cancelled,
              message: result.message,
            ),
          );
        case PaymentResultStatus.error:
          emit(
            state.copyWith(
              status: PaymentUiStatus.error,
              message: result.message,
            ),
          );
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: PaymentUiStatus.error,
          message: 'Не удалось выполнить покупку: $e',
        ),
      );
    }
  }

  Future<void> buyQarmetPackage(String productId) async {
    emit(
      state.copyWith(
        status: PaymentUiStatus.loading,
        message: null,
        purchasingQarmetProductId: productId,
      ),
    );
    try {
      final result = await _service.buyQarmetPackage(productId);
      switch (result.status) {
        case PaymentResultStatus.success:
          await refreshWallet(silent: true, forceRefresh: true);
          emit(
            state.copyWith(
              status: PaymentUiStatus.success,
              clearPurchasingQarmetProductId: true,
            ),
          );
        case PaymentResultStatus.cancelled:
          emit(
            state.copyWith(
              status: PaymentUiStatus.cancelled,
              message: result.message,
              clearPurchasingQarmetProductId: true,
            ),
          );
        case PaymentResultStatus.error:
          emit(
            state.copyWith(
              status: PaymentUiStatus.error,
              message: result.message,
              clearPurchasingQarmetProductId: true,
            ),
          );
      }
    } catch (e) {
      emit(
        state.copyWith(
          status: PaymentUiStatus.error,
          message: 'Не удалось выполнить покупку: $e',
          clearPurchasingQarmetProductId: true,
        ),
      );
    }
  }

  Future<void> spendPromotion({
    required String productId,
    required int positions,
  }) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForProductPromotion(
        productId: productId,
        positions: positions,
      );
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> spendTopPromotion(String productId) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForTopPromotion(productId);
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> spendUrgentPromotion(String productId) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForUrgentPromotion(productId);
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> spendHighlightPromotion(String productId) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForHighlightPromotion(productId);
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> spendAllInOnePromotion(String productId) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForAllInOnePromotion(productId);
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> spendPremiumBadge({required int cost}) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForPremiumBadge(cost: cost);
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> spendFrame({required int level, required int cost}) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForFrame(frameLevel: level, cost: cost);
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> spendBadge({required int level, required int cost}) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.spendForBadge(badgeLevel: level, cost: cost);
      await refreshWallet(silent: true, forceRefresh: true);
      emit(state.copyWith(status: PaymentUiStatus.success));
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  Future<void> restorePurchases() async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.restorePurchases();
      await refreshWallet(silent: true, forceRefresh: true);
      emit(
        state.copyWith(
          status: PaymentUiStatus.success,
          message: 'Покупки восстановлены',
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
  }

  void clearStatus() {
    emit(
      state.copyWith(
        status: PaymentUiStatus.idle,
        message: null,
        clearPurchasingQarmetProductId: true,
      ),
    );
  }
}
