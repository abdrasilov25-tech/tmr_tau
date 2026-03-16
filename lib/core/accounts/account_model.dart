class AccountModel {
  const AccountModel({
    required this.userId,
    required this.email,
    required this.refreshToken,
    this.accessToken,
  });

  final String userId;
  final String email;
  final String refreshToken;
  final String? accessToken;

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'email': email,
        'refreshToken': refreshToken,
        'accessToken': accessToken,
      };

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    return AccountModel(
      userId: json['userId'] as String,
      email: json['email'] as String,
      refreshToken: json['refreshToken'] as String,
      accessToken: json['accessToken'] as String?,
    );
  }
}

