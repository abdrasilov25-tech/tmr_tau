import 'package:equatable/equatable.dart';

/// Игрок в лобби поиска соперника для LIVE Battle.
class LiveBattleLobbyPlayer extends Equatable {
  const LiveBattleLobbyPlayer({
    required this.id,
    required this.label,
    this.avatarUrl,
    required this.isOnline,
  });

  final String id;
  /// Подпись в списке (@username, имя или email).
  final String label;
  final String? avatarUrl;
  final bool isOnline;

  @override
  List<Object?> get props => [id, label, avatarUrl, isOnline];
}
