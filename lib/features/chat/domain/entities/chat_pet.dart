import 'package:flutter/material.dart';

/// Каталог питомцев — hardcoded, не тянет из DB (цены/иконки меняются редко).
class ChatPetDefinition {
  const ChatPetDefinition({
    required this.id,
    required this.emoji,
    required this.name,
    required this.description,
    required this.price,
    required this.gradientColors,
  });

  final String id;
  final String emoji;
  final String name;
  final String description;

  /// 0 = бесплатно (разблокируется после 3 дней серии).
  final int price;
  final List<Color> gradientColors;

  bool get isFree => price == 0;
}

const List<ChatPetDefinition> kChatPetCatalog = [
  ChatPetDefinition(
    id: 'seriychik',
    emoji: '🐱',
    name: 'Серийчик',
    description: 'Бесплатный питомец за 3 дня переписки',
    price: 0,
    gradientColors: [Color(0xFFFF9A56), Color(0xFFFF6B35)],
  ),
  ChatPetDefinition(
    id: 'puppy',
    emoji: '🐶',
    name: 'Пёсик',
    description: 'Верный друг, всегда рядом',
    price: 100,
    gradientColors: [Color(0xFFFFD6A5), Color(0xFFFFB347)],
  ),
  ChatPetDefinition(
    id: 'panda',
    emoji: '🐼',
    name: 'Панда',
    description: 'Редкий и ленивый — идеален',
    price: 200,
    gradientColors: [Color(0xFFD1D1D1), Color(0xFF888888)],
  ),
  ChatPetDefinition(
    id: 'foxy',
    emoji: '🦊',
    name: 'Лисёнок',
    description: 'Хитрый и стильный',
    price: 300,
    gradientColors: [Color(0xFFFF7043), Color(0xFFE64A19)],
  ),
  ChatPetDefinition(
    id: 'frog',
    emoji: '🐸',
    name: 'Лягушонок',
    description: 'Весёлый зелёный друг',
    price: 120,
    gradientColors: [Color(0xFF69F0AE), Color(0xFF00C853)],
  ),
  ChatPetDefinition(
    id: 'butterfly',
    emoji: '🦋',
    name: 'Бабочка',
    description: 'Порхает между сообщениями',
    price: 150,
    gradientColors: [Color(0xFFCE93D8), Color(0xFF9C27B0)],
  ),
  ChatPetDefinition(
    id: 'koala',
    emoji: '🐨',
    name: 'Коала',
    description: 'Расслабленный и милый',
    price: 250,
    gradientColors: [Color(0xFFB0BEC5), Color(0xFF607D8B)],
  ),
  ChatPetDefinition(
    id: 'tiger',
    emoji: '🐯',
    name: 'Тигрёнок',
    description: 'Дерзкий и энергичный',
    price: 350,
    gradientColors: [Color(0xFFFFCC02), Color(0xFFFF8F00)],
  ),
  ChatPetDefinition(
    id: 'lion',
    emoji: '🦁',
    name: 'Лёв',
    description: 'Царь чата, не меньше',
    price: 400,
    gradientColors: [Color(0xFFFFD54F), Color(0xFFFF8F00)],
  ),
  ChatPetDefinition(
    id: 'dragon',
    emoji: '🐉',
    name: 'Дракон',
    description: 'Легендарный питомец',
    price: 500,
    gradientColors: [Color(0xFF80CBC4), Color(0xFF00695C)],
  ),
  ChatPetDefinition(
    id: 'star',
    emoji: '⭐',
    name: 'Звёздочка',
    description: 'Яркий и неповторимый',
    price: 600,
    gradientColors: [Color(0xFFFFF176), Color(0xFFFDD835)],
  ),
  ChatPetDefinition(
    id: 'unicorn',
    emoji: '🦄',
    name: 'Единорог',
    description: 'Самый редкий питомец',
    price: 800,
    gradientColors: [Color(0xFFF48FB1), Color(0xFFE91E63)],
  ),
];

ChatPetDefinition? petById(String id) {
  try {
    return kChatPetCatalog.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
}
