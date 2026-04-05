import 'dart:convert';

/// Стикер на кадре сторис (позиция в долях кадра + полезная нагрузка).
class StoryOverlayItem {
  const StoryOverlayItem({
    required this.id,
    required this.type,
    required this.nx,
    required this.ny,
    required this.data,
  });

  final String id;
  /// text, hashtag, mention, link, location, poll, question, countdown,
  /// image, gif, add_yours, frame, notify, slider, food, avatar
  final String type;
  /// Центр по горизонтали, 0..1 (0 слева).
  final double nx;
  /// Центр по вертикали, 0..1 (0 сверху).
  final double ny;
  final Map<String, dynamic> data;

  StoryOverlayItem copyWith({
    String? id,
    String? type,
    double? nx,
    double? ny,
    Map<String, dynamic>? data,
  }) {
    return StoryOverlayItem(
      id: id ?? this.id,
      type: type ?? this.type,
      nx: nx ?? this.nx,
      ny: ny ?? this.ny,
      data: data ?? Map<String, dynamic>.from(this.data),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'nx': nx,
        'ny': ny,
        'data': data,
      };

  factory StoryOverlayItem.fromJson(Map<String, dynamic> j) {
    return StoryOverlayItem(
      id: j['id'] as String,
      type: j['type'] as String,
      nx: (j['nx'] as num).toDouble(),
      ny: (j['ny'] as num).toDouble(),
      data: Map<String, dynamic>.from(j['data'] as Map? ?? {}),
    );
  }

  static List<StoryOverlayItem> listFromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return [];
    return decoded
        .map((e) => StoryOverlayItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static String listToJson(List<StoryOverlayItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
}
