import 'package:flutter/foundation.dart';

/// Флаги объявления (срочно / топ / торг / даром) с локальными [notifyListeners],
/// чтобы не вызывать [setState] у всей страницы формы.
class ProductListingPromoFlagsController extends ChangeNotifier {
  ProductListingPromoFlagsController({
    this.onGiveawayEnabled,
    bool isUrgent = false,
    bool isTop = false,
    bool isNegotiable = false,
    bool isGiveaway = false,
  })  : _isUrgent = isUrgent,
        _isTop = isTop,
        _isNegotiable = isNegotiable,
        _isGiveaway = isGiveaway;

  /// Сброс цены в «0», когда включают «Отдам даром».
  final VoidCallback? onGiveawayEnabled;

  bool _isUrgent;
  bool _isTop;
  bool _isNegotiable;
  bool _isGiveaway;

  bool get isUrgent => _isUrgent;
  bool get isTop => _isTop;
  bool get isNegotiable => _isNegotiable;
  bool get isGiveaway => _isGiveaway;

  void setUrgent(bool v) {
    if (_isUrgent == v) return;
    _isUrgent = v;
    notifyListeners();
  }

  void setTop(bool v) {
    if (_isTop == v) return;
    _isTop = v;
    notifyListeners();
  }

  void setNegotiable(bool v) {
    if (_isGiveaway || _isNegotiable == v) return;
    _isNegotiable = v;
    notifyListeners();
  }

  void setGiveaway(bool v) {
    if (_isGiveaway == v) {
      if (v) return;
      _isGiveaway = false;
      notifyListeners();
      return;
    }
    _isGiveaway = v;
    if (v) {
      if (_isNegotiable) _isNegotiable = false;
      onGiveawayEnabled?.call();
    }
    notifyListeners();
  }
}
