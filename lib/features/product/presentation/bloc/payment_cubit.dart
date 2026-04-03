import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/services/payment_service.dart';
import '../../domain/entities/qarmet_promotion_history_item.dart';
import '../../domain/entities/qarmet_product.dart';

enum PaymentUiStatus { idle, loading, success, error, cancelled }

class PaymentUiState {
  const PaymentUiState({
    this.status = PaymentUiStatus.idle,
    this.message,
    this.balance = 0,
    this.catalog = const <QarmetProduct>[],
    this.isOfficialPageActive = false,
    this.cosmeticsLifetimeUnlocked = false,
    this.promotionHistory = const <QarmetPromotionHistoryItem>[],
    this.purchasingQarmetProductId,
  });

  final PaymentUiStatus status;
  final String? message;
  final int balance;
  final List<QarmetProduct> catalog;
  final bool isOfficialPageActive;
  final bool cosmeticsLifetimeUnlocked;
  final List<QarmetPromotionHistoryItem> promotionHistory;

  /// Покупка пакета Qarmet из магазина (IAP). Пока идёт — блокируем только этот SKU,
  /// а не все кнопки при [status] == loading.
  final String? purchasingQarmetProductId;

  /// Полное обновление кошелька / init: глушим все действия с Qarmet.
  bool get isWalletWideBusy =>
      status == PaymentUiStatus.loading && purchasingQarmetProductId == null;

  /// Можно нажать «купить» для этого productId (остальные пакеты остаются активными).
  bool canTapBuyQarmetPackage(String productId) {
    if (status != PaymentUiStatus.loading) return true;
    return purchasingQarmetProductId != null &&
        purchasingQarmetProductId != productId;
  }

  PaymentUiState copyWith({
    PaymentUiStatus? status,
    String? message,
    int? balance,
    List<QarmetProduct>? catalog,
    bool? isOfficialPageActive,
    bool? cosmeticsLifetimeUnlocked,
    List<QarmetPromotionHistoryItem>? promotionHistory,
    String? purchasingQarmetProductId,
    bool clearPurchasingQarmetProductId = false,
  }) {
    return PaymentUiState(
      status: status ?? this.status,
      message: message,
      balance: balance ?? this.balance,
      catalog: catalog ?? this.catalog,
      isOfficialPageActive: isOfficialPageActive ?? this.isOfficialPageActive,
      cosmeticsLifetimeUnlocked:
          cosmeticsLifetimeUnlocked ?? this.cosmeticsLifetimeUnlocked,
      promotionHistory: promotionHistory ?? this.promotionHistory,
      purchasingQarmetProductId: clearPurchasingQarmetProductId
          ? null
          : (purchasingQarmetProductId ?? this.purchasingQarmetProductId),
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
      await _service.initStore();
      final mem = _service.getCachedWalletSnapshot();
      final disk = mem ?? await _service.getPersistentWalletSnapshot();
      final hasWarmData = mem != null || disk != null;
      final snap = mem ?? disk;
      if (snap != null) {
        emit(
          state.copyWith(
            status: PaymentUiStatus.idle,
            message: null,
            balance: snap.balance,
            catalog: snap.catalog,
            isOfficialPageActive: snap.isOfficialPageActive,
            cosmeticsLifetimeUnlocked: snap.cosmeticsLifetimeUnlocked,
            promotionHistory: snap.promotionHistory,
          ),
        );
      } else {
        emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
      }
      await refreshWallet(silent: hasWarmData, forceRefresh: false);
    } catch (e) {
      emit(
        state.copyWith(status: PaymentUiStatus.error, message: e.toString()),
      );
    }
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
      emit(
        state.copyWith(
          status: PaymentUiStatus.idle,
          message: null,
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
