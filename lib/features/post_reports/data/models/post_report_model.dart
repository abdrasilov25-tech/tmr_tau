import '../../domain/entities/post_report_entity.dart';

class PostReportModel extends PostReportEntity {
  const PostReportModel({
    required super.id,
    required super.postId,
    required super.reporterId,
    required super.reason,
    super.comment,
    required super.createdAt,
    super.postImageUrl,
    super.postVideoUrl,
    super.postCaption,
  });

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.parse(value);
    throw FormatException('Invalid datetime: $value');
  }

  factory PostReportModel.fromJson(Map<String, dynamic> json) {
    final posts = json['posts'];
    Map<String, dynamic>? postMap;
    if (posts is Map) {
      postMap = Map<String, dynamic>.from(posts);
    }

    return PostReportModel(
      id: json['id'] as String,
      postId: json['post_id'] as String,
      reporterId: json['reporter_id'] as String,
      reason: json['reason'] as String,
      comment: json['comment'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      postImageUrl: (postMap?['image_url'] as String?) ?? '',
      postVideoUrl: (postMap?['video_url'] as String?) ?? '',
      postCaption: (postMap?['caption'] as String?) ?? '',
    );
  }
}

