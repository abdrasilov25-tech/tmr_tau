import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    this.name,
    this.avatarUrl,
    this.bio,
    this.followersCount = 0,
    this.followingCount = 0,
  });

  final String id;
  final String email;
  final String? name;
  final String? avatarUrl;
  final String? bio;
  final int followersCount;
  final int followingCount;

  @override
  List<Object?> get props =>
      [id, email, name, avatarUrl, bio, followersCount, followingCount];
}
