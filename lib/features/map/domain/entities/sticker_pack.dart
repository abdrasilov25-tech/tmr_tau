class StickerPackDefinition {
  const StickerPackDefinition({
    required this.id,
    required this.name,
    required this.emoji,
    required this.stickers,
    this.isLimited = false,
  });

  final String id;
  final String name;
  final String emoji;
  final List<String> stickers;
  final bool isLimited;

  static const all = [
    StickerPackDefinition(
      id: 'animals',
      name: 'Животные',
      emoji: '🐾',
      stickers: ['🐻', '🦊', '🐺', '🦁', '🐯', '🐨', '🦝', '🐼'],
    ),
    StickerPackDefinition(
      id: 'kazakhstan',
      name: 'Казахстан',
      emoji: '🇰🇿',
      stickers: ['🏔️', '🦅', '🌾', '🐎', '🌟', '☀️', '🏕️', '🌿'],
    ),
    StickerPackDefinition(
      id: 'seasonal_newyear',
      name: 'Новый год',
      emoji: '🎄',
      stickers: ['🎄', '❄️', '🎁', '⛄', '🌟', '🎅', '🔔', '✨'],
      isLimited: true,
    ),
  ];

  static const costQarmet = 500;
}

class MapMarkerSticker {
  const MapMarkerSticker({required this.productId, required this.sticker});
  final String productId;
  final String sticker;
}
