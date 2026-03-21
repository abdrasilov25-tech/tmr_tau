import 'post_entity.dart';

/// Одна страница ленты публикаций (подписки или рекомендации).
class PublicationFeedPageResult {
  const PublicationFeedPageResult({
    required this.posts,
    required this.nextOffset,
  });

  final List<PostEntity> posts;
  /// Подписки: следующий offset в запросе; рекомендации: курсор по «сырой» выборке из БД.
  final int nextOffset;
}
