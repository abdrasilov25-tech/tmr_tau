/// Supabase table and column names. Keep in sync with schema.sql.
class SupabaseConstants {
  SupabaseConstants._();

  static const String usersTable = 'users';
  /// Заметка к сторис и локация (RLS: см. migrations/20260327140000_user_story_settings.sql).
  static const String userStorySettingsTable = 'user_story_settings';
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
  static const String postCommentLikesTable = 'post_comment_likes';
  static const String productCommentLikesTable = 'product_comment_likes';
  static const String repostsTable = 'reposts';
  static const String postSavesTable = 'post_saves';
  /// Просмотры публикаций в ленте (персональные рекомендации).
  static const String publicationFeedImpressionsTable =
      'publication_feed_impressions';
  static const String messagesTable = 'messages';
  static const String messageReactionsTable = 'message_reactions';
  static const String chatGroupsTable = 'chat_groups';
  static const String chatGroupMembersTable = 'chat_group_members';
  static const String chatGroupMessagesTable = 'chat_group_messages';
  /// Автомодерация городского чата (RLS: только своя строка).
  static const String cityChatUserModerationTable = 'city_chat_user_moderation';
  static const String userChannelsTable = 'user_channels';
  static const String channelMessagesTable = 'channel_messages';
  static const String channelSubscribersTable = 'channel_subscribers';
  static const String liveBattlesTable = 'live_battles';
  static const String liveBattleEventsTable = 'live_battle_events';
  static const String liveBattleResultsTable = 'live_battle_results';
  static const String giftCatalogTable = 'gift_catalog';
  /// Прямой эфир (Agora): см. migrations/20260404180000_live_rooms.sql.
  static const String liveRoomsTable = 'live_rooms';
  /// «Тап судьбы»: см. migrations/20260404220000_tap_game.sql.
  static const String tapGameSessionsTable = 'tap_game_sessions';
  static const String tapGameScoresTable = 'tap_game_scores';

  static const String bucketProducts = 'products';
  static const String bucketStories = 'stories';
  static const String bucketPosts = 'posts';
  static const String bucketAvatars = 'avatars';
}
