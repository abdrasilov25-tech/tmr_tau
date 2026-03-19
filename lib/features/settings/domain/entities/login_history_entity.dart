import 'package:equatable/equatable.dart';

class LoginHistoryEntity extends Equatable {
  const LoginHistoryEntity({
    required this.id,
    required this.userId,
    required this.loggedInAt,
    this.ipAddress,
    this.userAgent,
  });

  final String id;
  final String userId;
  final DateTime loggedInAt;
  final String? ipAddress;
  final String? userAgent;

  @override
  List<Object?> get props => [
        id,
        userId,
        loggedInAt,
        ipAddress,
        userAgent,
      ];
}

