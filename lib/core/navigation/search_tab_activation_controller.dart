import 'package:flutter/foundation.dart';

/// Управляет отложенной загрузкой товаров на вкладке «Поиск»: до первого
/// открытия вкладки сеть не дергается.
class SearchTabActivationController extends ChangeNotifier {
  bool _productsLoadPrimed = false;

  bool get productsLoadPrimed => _productsLoadPrimed;

  void markSearchTabSelected() {
    if (_productsLoadPrimed) return;
    _productsLoadPrimed = true;
    notifyListeners();
  }

  /// После выхода из аккаунта — снова ждём первого открытия поиска.
  void reset() {
    _productsLoadPrimed = false;
    notifyListeners();
  }
}
