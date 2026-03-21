/// Supabase table and column names. Keep in sync with schema.sql.
class SupabaseConstants {
  SupabaseConstants._();

  static const String usersTable = 'users';
  static const String categoriesTable = 'categories';
  static const String productsTable = 'products';
  static const String productLikesTable = 'product_likes';
  static const String productCommentsTable = 'product_comments';
  static const String productRepostsTable = 'product_reposts';
  static const String followersTable = 'followers';
  static const String storiesTable = 'stories';
  static const String storyViewsTable = 'story_views';
  static const String storyRepliesTable = 'story_replies';
  static const String hiddenStoriesTable = 'hidden_stories';
  static const String notificationsTable = 'notifications';
  static const String favoritesTable = 'favorites';
  static const String ordersTable = 'orders';
  static const String postsTable = 'posts';
  static const String postLikesTable = 'post_likes';
  static const String postDislikesTable = 'post_dislikes';
  static const String postCommentsTable = 'post_comments';
  static const String repostsTable = 'reposts';
  static const String postSavesTable = 'post_saves';
  /// Просмотры публикаций в ленте (персональные рекомендации).
  static const String publicationFeedImpressionsTable =
      'publication_feed_impressions';
  static const String messagesTable = 'messages';
  static const String chatGroupsTable = 'chat_groups';
  static const String chatGroupMembersTable = 'chat_group_members';
  static const String chatGroupMessagesTable = 'chat_group_messages';
  static const String userChannelsTable = 'user_channels';
  static const String channelMessagesTable = 'channel_messages';

  static const String bucketProducts = 'products';
  static const String bucketStories = 'stories';
  static const String bucketPosts = 'posts';
  static const String bucketAvatars = 'avatars';
}
