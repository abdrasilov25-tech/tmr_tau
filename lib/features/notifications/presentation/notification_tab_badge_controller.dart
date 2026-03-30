import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/repositories/notifications_repository.dart';

/// Бейджи вкладок «Публикации» и «Новости»: непрочитанные уведомления по типу ленты.
class NotificationTabBadgeController extends ChangeNotifier {
  NotificationTabBadgeController({
    required NotificationsRepository notificationsRepository,
  }) : _repository = notificationsRepository;

  final NotificationsRepository _repository;

  int _publications = 0;
  int _news = 0;
  bool _busy = false;

  int get publicationsUnread => _publications;
  int get newsUnread => _news;

  String get publicationsBadgeLabel => _shortLabel(_publications);
  String get newsBadgeLabel => _shortLabel(_news);

  static String _shortLabel(int n) {
    if (n <= 0) return '';
    if (n > 99) return '99+';
    return '$n';
  }

  void clear() {
    if (_publications != 0 || _news != 0) {
      _publications = 0;
      _news = 0;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) {
      clear();
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      final counts = await _repository.getFeedUnreadCounts(uid);
      final changed =
          counts.publications != _publications || counts.news != _news;
      if (changed) {
        _publications = counts.publications;
        _news = counts.news;
        notifyListeners();
      }
    } catch (_) {
      // оставляем последнее значение
    } finally {
      _busy = false;
    }
  }
}
