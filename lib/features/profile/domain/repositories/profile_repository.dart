import '../entities/seller_profile_entity.dart';

abstract class ProfileRepository {
  Future<SellerProfileEntity?> getSellerProfile(
    String sellerId, {
    String? currentUserId,
  });
  /// Verified/official accounts (e.g. tmr_tau official page), for search top.
  Future<List<SellerProfileEntity>> getVerifiedUsers();
  Future<void> toggleFollow(String followerId, String followingId);
  Future<void> updateProfile({
    required String userId,
    String? name,
    String? avatarUrl,
    String? bio,
  });
}
