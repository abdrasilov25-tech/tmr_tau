/// Нормализация номера РК под префикс +7 (10 национальных цифр).
abstract final class KazakhstanPhone {
  KazakhstanPhone._();

  static String stripToTenDigits(String input) {
    var d = input.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('8') && d.length >= 11) {
      d = d.substring(1);
    }
    if (d.startsWith('7') && d.length >= 11) {
      d = d.substring(1);
    }
    if (d.length > 10) {
      d = d.substring(d.length - 10);
    }
    return d;
  }

  static String fullInternational(String tenDigits) => '+7$tenDigits';

  static bool isValidNationalTen(String ten) => RegExp(r'^\d{10}$').hasMatch(ten);
}
