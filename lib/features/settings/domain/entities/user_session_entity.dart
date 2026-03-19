import 'package:equatable/equatable.dart';

class UserSessionEntity extends Equatable {
  const UserSessionEntity({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.lastSeenAt,
    this.device,
    this.ipAddress,
  });

  final String id;
  final String userId;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final String? device;
  final String? ipAddress;

  @override
  List<Object?> get props => [
        id,
        userId,
        createdAt,
        lastSeenAt,
        device,
        ipAddress,
      ];
}

