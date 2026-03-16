class AccountModel {
  const AccountModel({
    required this.userId,
    required this.email,
    required this.refreshToken,
    this.accessToken,
    this.username,
  });

  final String userId;
  final String email;
  final String refreshToken;
  final String? accessToken;
  final String? username;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'refreshToken': refreshToken,
        'accessToken': accessToken,
        'username': username,
      };

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    return AccountModel(
      userId: json['userId'] as String,
      email: json['email'] as String,
      refreshToken: json['refreshToken'] as String,
      accessToken: json['accessToken'] as String?,
      username: json['username'] as String?,
    );
  }
}

