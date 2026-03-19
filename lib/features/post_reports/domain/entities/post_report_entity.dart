import 'package:equatable/equatable.dart';

class PostReportEntity extends Equatable {
  const PostReportEntity({
    required this.id,
    required this.postId,
    required this.reporterId,
    required this.reason,
    this.comment,
    required this.createdAt,
    // Preview fields for UI (comes from join with `posts`)
    this.postImageUrl,
    this.postVideoUrl,
    this.postCaption,
  });

  final String id;
  final String postId;
  final String reporterId;
  final String reason;
  final String? comment;
  final DateTime createdAt;

  final String? postImageUrl;
  final String? postVideoUrl;
  final String? postCaption;

  @override
  List<Object?> get props => [
        id,
        postId,
        reporterId,
        reason,
        comment,
        createdAt,
        postImageUrl,
        postVideoUrl,
        postCaption,
      ];
}

