import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/post_report_entity.dart';
import '../../domain/repositories/post_reports_repository.dart';
import '../models/post_report_model.dart';

class PostReportsRepositoryImpl implements PostReportsRepository {
  PostReportsRepositoryImpl(this._client);

  final SupabaseClient _client;

  static const String _table = 'post_reports';

  @override
  Future<void> createReport({
    required String postId,
    required String reporterId,
    required String reason,
    String? comment,
  }) async {
    await _client.from(_table).insert({
      'post_id': postId,
      'reporter_id': reporterId,
      'reason': reason,
      'comment': comment ?? '',
    });
  }

  @override
  Future<List<PostReportEntity>> getMyReportsCursor({
    required String reporterId,
    int limit = 10,
    DateTime? lastCreatedAt,
  }) async {
    final res = await (lastCreatedAt == null
        ? _client
            .from(_table)
            .select('*, posts(image_url, video_url, caption)')
            .eq('reporter_id', reporterId)
            .order('created_at', ascending: false)
            .limit(limit)
        : _client
            .from(_table)
            .select('*, posts(image_url, video_url, caption)')
            .eq('reporter_id', reporterId)
            .lt('created_at', lastCreatedAt.toIso8601String())
            .order('created_at', ascending: false)
            .limit(limit));

    return (res as List)
        .map((e) => PostReportModel.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }
}

