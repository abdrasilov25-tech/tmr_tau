import '../entities/post_report_entity.dart';

abstract class PostReportsRepository {
  Future<void> createReport({
    required String postId,
    required String reporterId,
    required String reason,
    String? comment,
  });

  /// Returns current user's reports ordered by `created_at DESC`.
  ///
  /// Cursor pagination: when [lastCreatedAt] is provided, the query loads
  /// only records with `created_at < lastCreatedAt`.
  Future<List<PostReportEntity>> getMyReportsCursor({
    required String reporterId,
    int limit = 10,
    DateTime? lastCreatedAt,
  });
}

