import 'package:equatable/equatable.dart';

/// Результат вызова бэкенда: ссылка на оплату и id заказа.
///
/// **Платёж:** URL открывается во внешнем браузере / WebView; секреты карт не в приложении.
class PromotionCheckoutSession extends Equatable {
  const PromotionCheckoutSession({
    required this.checkoutUrl,
    required this.orderId,
    required this.provider,
    this.amountMinor,
    this.currency = 'KZT',
  });

  final String checkoutUrl;
  final String orderId;

  /// Идентификатор провайдера оплаты.
  final String provider;
  final int? amountMinor;
  final String currency;

  @override
  List<Object?> get props =>
      [checkoutUrl, orderId, provider, amountMinor, currency];
}
