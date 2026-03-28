import 'package:equatable/equatable.dart';

class PostEntity extends Equatable {
  const PostEntity({
    required this.id,
    required this.userId,
    this.kind = 'news',
    this.imageUrl = '',
    this.imageUrls = const [],
    this.caption = '',
    this.videoUrl,
    this.videoDurationSeconds = 0,
    required this.createdAt,
    this.likesCount = 0,
    this.dislikesCount = 0,
    this.commentsCount = 0,
    this.repostsCount = 0,
    this.userName,
    this.userAvatarUrl,
    this.isLikedByMe = false,
    this.isDislikedByMe = false,
    this.isRepostedByMe = false,
    this.isSavedByMe = false,
    // Recommendation fields (optional, backward-compatible)
    this.viewsCount = 0,
    this.savedCount = 0,
    this.category = '',
    this.latitude,
    this.longitude,
  });

  final String id;
  final String userId;
  final String kind;
  final String imageUrl;
  /// Несколько фото (новости). Пусто = только [imageUrl].
  final List<String> imageUrls;
  final String caption;
  final String? videoUrl;
  final int videoDurationSeconds;
  final DateTime createdAt;
  final int likesCount;
  final int dislikesCount;
  final int commentsCount;
  final int repostsCount;
  final String? userName;
  final String? userAvatarUrl;
  final bool isLikedByMe;
  final bool isDislikedByMe;
  final bool isRepostedByMe;
  final bool isSavedByMe;

  // ── Recommendation fields ──────────────────────────────────
  /// Количество просмотров в ленте (из publication_feed_impressions).
  final int viewsCount;

  /// Денормализованный счётчик сохранений (из post_saves).
  final int savedCount;

  /// Свободная категория поста для персонализации.
  final String category;

  /// GPS-координаты поста (nullable = нет геопривязки).
  final double? latitude;
  final double? longitude;

  /// `true` если у поста есть геопривязка.
  bool get hasGeo => latitude != null && longitude != null;

  /// Базовый engagement-score по формуле требований:
  ///   views×1 + likes×3 + comments×5 + saves×7
  double get engagementScore =>
      viewsCount * 1.0 + likesCount * 3.0 + commentsCount * 5.0 + savedCount * 7.0;

  /// Все URL фото для карусели (мульти или одно из legacy `image_url`).
  List<String> get displayImageUrls {
    if (imageUrls.isNotEmpty) return List.unmodifiable(imageUrls);
    if (imageUrl.isNotEmpty) return [imageUrl];
    return const [];
  }

  PostEntity copyWith({
    String? id,
    String? userId,
    String? kind,
    String? imageUrl,
    List<String>? imageUrls,
    String? caption,
    String? videoUrl,
    int? videoDurationSeconds,
    bool clearImage = false,
    bool clearVideo = false,
    DateTime? createdAt,
    int? likesCount,
    int? dislikesCount,
    int? commentsCount,
    int? repostsCount,
    String? userName,
    String? userAvatarUrl,
    bool? isLikedByMe,
    bool? isDislikedByMe,
    bool? isRepostedByMe,
    bool? isSavedByMe,
    int? viewsCount,
    int? savedCount,
    String? category,
    double? latitude,
    double? longitude,
  }) {
    return PostEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      kind: kind ?? this.kind,
      imageUrl: clearImage ? '' : (imageUrl ?? this.imageUrl),
      imageUrls: clearImage ? const [] : (imageUrls ?? this.imageUrls),
      caption: caption ?? this.caption,
      videoUrl: clearVideo ? null : (videoUrl ?? this.videoUrl),
      videoDurationSeconds:
          clearVideo ? 0 : (videoDurationSeconds ?? this.videoDurationSeconds),
      createdAt: createdAt ?? this.createdAt,
      likesCount: likesCount ?? this.likesCount,
      dislikesCount: dislikesCount ?? this.dislikesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      repostsCount: repostsCount ?? this.repostsCount,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      isDislikedByMe: isDislikedByMe ?? this.isDislikedByMe,
      isRepostedByMe: isRepostedByMe ?? this.isRepostedByMe,
      isSavedByMe: isSavedByMe ?? this.isSavedByMe,
      viewsCount: viewsCount ?? this.viewsCount,
      savedCount: savedCount ?? this.savedCount,
      category: category ?? this.category,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  @override
  List<Object?> get props => [
        id,
        userId,
        kind,
        imageUrl,
        imageUrls,
        caption,
        videoUrl,
        videoDurationSeconds,
        createdAt,
        likesCount,
        dislikesCount,
        commentsCount,
        repostsCount,
        userName,
        userAvatarUrl,
        isLikedByMe,
        isDislikedByMe,
        isRepostedByMe,
        isSavedByMe,
        viewsCount,
        savedCount,
        category,
        latitude,
        longitude,
      ];
}
