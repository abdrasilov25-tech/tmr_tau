import '../../domain/entities/post_entity.dart';

class PostModel extends PostEntity {
  const PostModel({
    required super.id,
    required super.userId,
    super.kind = 'news',
    super.imageUrl = '',
    super.imageUrls = const [],
    super.caption = '',
    super.videoUrl,
    super.videoDurationSeconds = 0,
    required super.createdAt,
    super.likesCount = 0,
    super.dislikesCount = 0,
    super.commentsCount = 0,
    super.viewsCount = 0,
    super.repostsCount = 0,
    super.userName,
    super.userAvatarUrl,
    super.isLikedByMe = false,
    super.isDislikedByMe = false,
    super.isRepostedByMe = false,
    super.isSavedByMe = false,
    super.latitude,
    super.longitude,
    super.distanceKm,
    super.isPromoted = false,
    super.promotedUntil,
    super.city,
    super.isAnonymous = false,
    super.locationLabel,
    super.pollQuestion,
    super.pollOptions = const [],
    super.pollVoteCounts = const [],
    super.myPollVoteIndex,
    super.authorOfficialPageActive = false,
    super.isFollowingAuthor = false,
    super.musicTitle,
    super.musicArtist,
    super.musicPreviewUrl,
  });

  factory PostModel.fromJson(Map<String, dynamic> json) {
    final rawKind = (json['kind'] as String?)?.trim().toLowerCase() ?? '';
    final safeKind = rawKind == 'news'
        ? 'news'
        : 'publication';
    List<String> urls = const [];
    final rawUrls = json['image_urls'];
    if (rawUrls is List) {
      urls = rawUrls
          .map((e) => e == null ? '' : e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    List<String> pollOpts = const [];
    final rawPoll = json['poll_options'];
    if (rawPoll is List) {
      pollOpts = rawPoll
          .map((e) => e == null ? '' : e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    final pq = (json['poll_question'] as String?)?.trim();
    String? optStr(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      kind: safeKind,
      imageUrl: (json['image_url'] as String?) ?? '',
      imageUrls: urls,
      caption: (json['caption'] as String?) ?? '',
      videoUrl: json['video_url'] as String?,
      videoDurationSeconds: (json['video_duration_seconds'] as int?) ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      likesCount: (json['likes_count'] as int?) ?? 0,
      dislikesCount: (json['dislikes_count'] as int?) ?? 0,
      commentsCount: (json['comments_count'] as int?) ?? 0,
      viewsCount: (json['views_count'] as int?) ?? 0,
      repostsCount: (json['reposts_count'] as int?) ?? 0,
      userName: json['user_name'] as String?,
      userAvatarUrl: json['user_avatar'] as String?,
      isLikedByMe: (json['is_liked_by_me'] as bool?) ?? false,
      isDislikedByMe: (json['is_disliked_by_me'] as bool?) ?? false,
      isRepostedByMe: (json['is_reposted_by_me'] as bool?) ?? false,
      isSavedByMe: (json['is_saved_by_me'] as bool?) ?? false,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      isPromoted: (json['is_promoted'] as bool?) ?? false,
      promotedUntil: DateTime.tryParse((json['promoted_until'] ?? '').toString()),
      city: json['city'] as String?,
      isAnonymous: (json['is_anonymous'] as bool?) ?? false,
      locationLabel: json['location_label'] as String?,
      pollQuestion: pq != null && pq.isNotEmpty ? pq : null,
      pollOptions: pollOpts,
      pollVoteCounts: List<int>.filled(pollOpts.length, 0, growable: false),
      myPollVoteIndex: null,
      authorOfficialPageActive: (json['author_official_page_active'] as bool?) ?? false,
      isFollowingAuthor: (json['is_following_author'] as bool?) ?? false,
      musicTitle: optStr(json['music_title']),
      musicArtist: optStr(json['music_artist']),
      musicPreviewUrl: optStr(json['music_preview_url']),
    );
  }
}
