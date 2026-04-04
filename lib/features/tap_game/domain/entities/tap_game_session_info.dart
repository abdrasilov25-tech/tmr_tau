import 'package:equatable/equatable.dart';

class TapGameSessionInfo extends Equatable {
  const TapGameSessionInfo({
    required this.id,
    required this.startedAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endsAt;
  final bool isActive;

  bool get isOpen => isActive && DateTime.now().isBefore(endsAt);

  @override
  List<Object?> get props => [id, startedAt, endsAt, isActive];
}
