import 'package:equatable/equatable.dart';

/// Лучший зафиксированный счёт игрока на устройстве (зал славы, топ‑50).
class TapGameLocalHallEntry extends Equatable {
  const TapGameLocalHallEntry({
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    required this.bestScore,
    required this.updatedAt,
  });

  final String userId;
  final String displayName;
  final String? avatarUrl;
  final int bestScore;
  final DateTime updatedAt;

  TapGameLocalHallEntry copyWith({
    String? userId,
    String? displayName,
    String? avatarUrl,
    int? bestScore,
    DateTime? updatedAt,
  }) =>
      TapGameLocalHallEntry(
        userId: userId ?? this.userId,
        displayName: displayName ?? this.displayName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        bestScore: bestScore ?? this.bestScore,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'bestScore': bestScore,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static TapGameLocalHallEntry? fromJson(Map<String, dynamic>? m) {
    if (m == null) return null;
    final uid = m['userId']?.toString();
    if (uid == null || uid.isEmpty) return null;
    final name = m['displayName']?.toString().trim();
    final av = m['avatarUrl']?.toString();
    final sc = m['bestScore'];
    final score = sc is int ? sc : int.tryParse('$sc') ?? 0;
    DateTime at;
    try {
      at = DateTime.parse(m['updatedAt']?.toString() ?? '');
    } catch (e) {
      at = DateTime.now();
    }
    return TapGameLocalHallEntry(
      userId: uid,
      displayName: (name != null && name.isNotEmpty) ? name : 'Игрок',
      avatarUrl: (av != null && av.isNotEmpty) ? av : null,
      bestScore: score,
      updatedAt: at,
    );
  }

  @override
  List<Object?> get props =>
      [userId, displayName, avatarUrl, bestScore, updatedAt];
}
