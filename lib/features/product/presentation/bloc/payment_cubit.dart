import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/services/payment_service.dart';

enum PaymentUiStatus { idle, loading, success, error, cancelled }

class PaymentUiState {
  const PaymentUiState({
    this.status = PaymentUiStatus.idle,
    this.message,
  });

  final PaymentUiStatus status;
  final String? message;

  PaymentUiState copyWith({
    PaymentUiStatus? status,
    String? message,
  }) {
    return PaymentUiState(
      status: status ?? this.status,
      message: message,
    );
  }
}

class PaymentCubit extends Cubit<PaymentUiState> {
  PaymentCubit(this._service) : super(const PaymentUiState());

  final PaymentService _service;

  Future<void> initStore() async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.initStore();
      emit(state.copyWith(status: PaymentUiStatus.idle));
    } catch (e) {
      emit(state.copyWith(
        status: PaymentUiStatus.error,
        message: e.toString(),
      ));
    }
  }

  Future<void> buyBoost(String postId) async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    final result = await _service.buyBoost(postId: postId);
    switch (result.status) {
      case PaymentResultStatus.success:
        emit(state.copyWith(status: PaymentUiStatus.success));
      case PaymentResultStatus.cancelled:
        emit(state.copyWith(
          status: PaymentUiStatus.cancelled,
          message: result.message,
        ));
      case PaymentResultStatus.error:
        emit(state.copyWith(
          status: PaymentUiStatus.error,
          message: result.message,
        ));
    }
  }

  Future<void> buyPremium() async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    final result = await _service.buyPremium();
    switch (result.status) {
      case PaymentResultStatus.success:
        emit(state.copyWith(status: PaymentUiStatus.success));
      case PaymentResultStatus.cancelled:
        emit(state.copyWith(
          status: PaymentUiStatus.cancelled,
          message: result.message,
        ));
      case PaymentResultStatus.error:
        emit(state.copyWith(
          status: PaymentUiStatus.error,
          message: result.message,
        ));
    }
  }

  Future<void> restorePurchases() async {
    emit(state.copyWith(status: PaymentUiStatus.loading, message: null));
    try {
      await _service.restorePurchases();
      emit(state.copyWith(
        status: PaymentUiStatus.success,
        message: 'Покупки восстановлены',
      ));
    } catch (e) {
      emit(state.copyWith(
        status: PaymentUiStatus.error,
        message: e.toString(),
      ));
    }
  }

  void clearStatus() {
    emit(const PaymentUiState());
  }
}
