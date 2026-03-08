/// Supabase table and column names. Keep in sync with schema.sql.
class SupabaseConstants {
  SupabaseConstants._();

  static const String usersTable = 'users';
  static const String categoriesTable = 'categories';
  static const String productsTable = 'products';
  static const String productLikesTable = 'product_likes';
  static const String productCommentsTable = 'product_comments';
  static const String followersTable = 'followers';
  static const String storiesTable = 'stories';
  static const String storyRepliesTable = 'story_replies';
  static const String notificationsTable = 'notifications';
  static const String favoritesTable = 'favorites';
  static const String ordersTable = 'orders';
  static const String postsTable = 'posts';
  static const String postLikesTable = 'post_likes';
  static const String postDislikesTable = 'post_dislikes';
  static const String postCommentsTable = 'post_comments';
  static const String repostsTable = 'reposts';

  static const String bucketProducts = 'products';
  static const String bucketStories = 'stories';
  static const String bucketPosts = 'posts';
}
