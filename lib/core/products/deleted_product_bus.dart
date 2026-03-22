import 'dart:async';

/// Шина событий: товар удалён в БД — обновляем локальные списки (поиск, избранное, профиль).
final StreamController<String> _deletedProductController =
    StreamController<String>.broadcast();

Stream<String> get deletedProductIdsStream => _deletedProductController.stream;

void notifyProductDeleted(String productId) {
  if (!_deletedProductController.isClosed) {
    _deletedProductController.add(productId);
  }
}
