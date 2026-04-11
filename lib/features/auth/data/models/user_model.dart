import '../../domain/entities/app_user.dart';

class UserModel extends AppUser {
  const UserModel({
    required super.id,
    required super.email,
    super.name,
    super.username,
    super.avatarUrl,
    super.bio,
    super.residentNumber,
    super.followersCount,
    super.followingCount,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      name: json['name'] as String?,
      username: json['username'] as String?,
      avatarUrl: json['avatar'] as String?,
      bio: json['bio'] as String?,
      residentNumber: json['resident_number'] as String?,
      followersCount: json['followers_count'] as int? ?? 0,
      followingCount: json['following_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'username': username,
        'avatar': avatarUrl,
        'bio': bio,
        'resident_number': residentNumber,
        'followers_count': followersCount,
        'following_count': followingCount,
      };
}
