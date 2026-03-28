import 'package:equatable/equatable.dart';
import 'post_entity.dart';

/// Результат одной страницы рекомендованной ленты.
///
/// Содержит смешанную ленту (70% персонализация + 20% популярные + 10% новые)
/// и метаданные пагинации для следующего запроса.
class RecommendedFeedResult extends Equatable {
  const RecommendedFeedResult({
    required this.posts,
    required this.page,
    this.hasMore = true,
    this.personalizedCount = 0,
    this.popularCount = 0,
    this.newCount = 0,
  });

  /// Смешанный список постов для отображения.
  final List<PostEntity> posts;

  /// Номер страницы (0-based).
  final int page;

  /// Есть ли следующая страница.
  final bool hasMore;

  /// Диагностика: сколько постов пришло из каждого сегмента.
  final int personalizedCount;
  final int popularCount;
  final int newCount;

  @override
  List<Object?> get props => [posts, page, hasMore];
}
