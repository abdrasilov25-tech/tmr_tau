import 'dart:convert';

/// Encodes/decodes a shared-post DM payload.
///
/// **New format** (written by this class):
///   `__post_json__|<base64-encoded-JSON>`
///
/// **Legacy format** (read-only, backward compat):
///   `__post__|<url-encoded-postId>|<imageUrl>|<caption>|<authorName>|<videoUrl>|<likes>|<comments>|<reposts>`
class SharedPostMessage {
  const SharedPostMessage({
    required this.postId,
    required this.imageUrl,
    required this.caption,
    required this.authorName,
    required this.videoUrl,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.repostsCount = 0,
  });

  final String postId;
  final String imageUrl;
  final String caption;
  final String authorName;
  final String videoUrl;
  final int likesCount;
  final int commentsCount;
  final int repostsCount;

  static const String _newPrefix = '__post_json__|';
  static const String _legacyPrefix = '__post__|';

  /// Returns `true` for both the new and legacy prefixes — use this to block
  /// editing shared-post messages in the chat.
  static bool isSharedPost(String text) =>
      text.startsWith(_newPrefix) || text.startsWith(_legacyPrefix);

  /// Encodes this message into the new JSON-based format.
  String encode() {
    final json = jsonEncode({
      'post_id': postId,
      'image_url': imageUrl,
      'caption': caption,
      'author_name': authorName,
      'video_url': videoUrl,
      'likes_count': likesCount,
      'comments_count': commentsCount,
      'reposts_count': repostsCount,
    });
    return '$_newPrefix${base64Url.encode(utf8.encode(json))}';
  }

  /// Tries to parse both new and legacy formats. Returns `null` on failure.
  static SharedPostMessage? tryParse(String text) {
    if (text.startsWith(_newPrefix)) {
      return _parseNew(text.substring(_newPrefix.length));
    }
    if (text.startsWith(_legacyPrefix)) {
      return _parseLegacy(text);
    }
    return null;
  }

  static SharedPostMessage? _parseNew(String encoded) {
    try {
      final json = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
      final m = jsonDecode(json) as Map<String, dynamic>;
      final postId = (m['post_id'] as String?) ?? '';
      if (postId.isEmpty) return null;
      return SharedPostMessage(
        postId: postId,
        imageUrl: (m['image_url'] as String?) ?? '',
        caption: (m['caption'] as String?) ?? '',
        authorName: (m['author_name'] as String?) ?? 'Пользователь',
        videoUrl: (m['video_url'] as String?) ?? '',
        likesCount: (m['likes_count'] as int?) ?? 0,
        commentsCount: (m['comments_count'] as int?) ?? 0,
        repostsCount: (m['reposts_count'] as int?) ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  static SharedPostMessage? _parseLegacy(String text) {
    if (!text.startsWith('$_legacyPrefix|') && !text.startsWith(_legacyPrefix)) {
      return null;
    }
    String decode(String value) {
      try {
        return Uri.decodeComponent(value);
      } catch (_) {
        return value;
      }
    }

    // Remove the '__post__' prefix, then split by '|'
    final body = text.substring(_legacyPrefix.length);
    final parts = body.split('|');
    if (parts.isEmpty) return null;
    final postId = decode(parts[0]);
    if (postId.isEmpty) return null;

    int parseCount(int index) {
      if (parts.length <= index) return 0;
      return int.tryParse(parts[index]) ?? 0;
    }

    return SharedPostMessage(
      postId: postId,
      imageUrl: parts.length > 1 ? decode(parts[1]) : '',
      caption: parts.length > 2 ? decode(parts[2]) : '',
      authorName: parts.length > 3 ? decode(parts[3]) : 'Пользователь',
      videoUrl: parts.length > 4 ? decode(parts[4]) : '',
      likesCount: parseCount(5),
      commentsCount: parseCount(6),
      repostsCount: parseCount(7),
    );
  }
}
