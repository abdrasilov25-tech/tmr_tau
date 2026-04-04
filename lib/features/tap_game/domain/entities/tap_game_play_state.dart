import 'package:equatable/equatable.dart';

/// Ответ RPC tap_game_add_score.
class TapGameTapResult extends Equatable {
  const TapGameTapResult({
    required this.score,
    required this.staminaRemaining,
  });

  final int score;
  final int staminaRemaining;

  @override
  List<Object?> get props => [score, staminaRemaining];
}

/// Ответ tap_game_purchase_stamina.
class TapGameStaminaPurchaseResult extends Equatable {
  const TapGameStaminaPurchaseResult({
    required this.stamina,
    required this.added,
    required this.spent,
  });

  final int stamina;
  final int added;
  final int spent;

  @override
  List<Object?> get props => [stamina, added, spent];
}

/// Текущая строка игрока в сессии (очки + энергия).
class TapGameMyPlayState extends Equatable {
  const TapGameMyPlayState({
    required this.score,
    required this.staminaRemaining,
  });

  final int score;
  final int staminaRemaining;

  @override
  List<Object?> get props => [score, staminaRemaining];
}
