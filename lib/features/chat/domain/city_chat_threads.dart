class CityChatThread {
  const CityChatThread({
    required this.id,
    required this.emoji,
    required this.label,
  });

  final String id;
  final String emoji;
  final String label;
}

abstract final class CityChatThreads {
  static const String general = 'general';
  static const String roads = 'roads';
  static const String checks = 'checks';
  static const String market = 'market';
  static const String help = 'help';

  static const List<CityChatThread> all = <CityChatThread>[
    CityChatThread(id: general, emoji: '🧠', label: 'Общий'),
    CityChatThread(id: roads, emoji: '🚗', label: 'Дороги / пробки'),
    CityChatThread(id: checks, emoji: '🚓', label: 'Проверки'),
    CityChatThread(id: market, emoji: '💰', label: 'Барахолка'),
    CityChatThread(id: help, emoji: '🆘', label: 'Помощь'),
  ];
}
