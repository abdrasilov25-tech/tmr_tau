/// Ошибка сценария оплаты (Edge Function, сеть, конфигурация провайдера).
class MonetizationException implements Exception {
  MonetizationException(this.message);
  final String message;

  @override
  String toString() => message;
}
