import '../entities/seller_profile_entity.dart';

abstract class ProfileRepository {
  Future<SellerProfileEntity?> getSellerProfile(
    String sellerId, {
    String? currentUserId,
  });
  /// Verified/official accounts (e.g. tmr_tau official page), for search top.
  Future<List<SellerProfileEntity>> getVerifiedUsers();
  /// Users that the given user is following.
  Future<List<SellerProfileEntity>> getFollowingUsers(String followerId);
  /// Users that are following the given user.
  Future<List<SellerProfileEntity>> getFollowersUsers(String followingId);
  Future<void> toggleFollow(String followerId, String followingId);
  Future<void> updateProfile({
    required String userId,
    String? name,
    String? avatarUrl,
    String? bio,
    String? username,
    String? gender,
  });
}
