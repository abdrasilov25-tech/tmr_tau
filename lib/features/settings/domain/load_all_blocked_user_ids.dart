import 'repositories/settings_repository.dart';

/// Постранично загружает все id заблокированных пользователей (для фильтра ленты/поиска).
Future<Set<String>> loadAllBlockedUserIds({
  required SettingsRepository repository,
  required String blockerId,
  int pageSize = 100,
}) async {
  final out = <String>{};
  DateTime? cursor;
  while (true) {
    final batch = await repository.getBlockedUsersCursor(
      blockerId: blockerId,
      limit: pageSize,
      lastBlockedAt: cursor,
    );
    if (batch.isEmpty) break;
    for (final b in batch) {
      out.add(b.blockedUserId);
    }
    if (batch.length < pageSize) break;
    cursor = batch.last.blockedAt;
  }
  return out;
}
