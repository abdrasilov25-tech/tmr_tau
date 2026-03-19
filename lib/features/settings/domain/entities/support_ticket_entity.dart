import 'package:equatable/equatable.dart';

class SupportTicketEntity extends Equatable {
  const SupportTicketEntity({
    required this.id,
    required this.userId,
    required this.title,
    required this.description,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String title;
  final String description;
  final DateTime createdAt;

  @override
  List<Object?> get props => [
        id,
        userId,
        title,
        description,
        createdAt,
      ];
}

