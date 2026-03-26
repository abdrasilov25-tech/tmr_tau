import 'package:flutter_test/flutter_test.dart';
import 'package:tmr_tau/features/post/domain/entities/post_entity.dart';

void main() {
  final t0 = DateTime(2024, 1, 1);

  group('PostEntity', () {
    test('displayImageUrls: приоритет imageUrls', () {
      final p = PostEntity(
        id: '1',
        userId: 'u',
        imageUrl: 'https://legacy.jpg',
        imageUrls: const ['https://a.jpg', 'https://b.jpg'],
        createdAt: t0,
      );
      expect(p.displayImageUrls, ['https://a.jpg', 'https://b.jpg']);
    });

    test('displayImageUrls: пустые imageUrls — legacy imageUrl', () {
      final p = PostEntity(
        id: '1',
        userId: 'u',
        imageUrl: 'https://only.jpg',
        createdAt: t0,
      );
      expect(p.displayImageUrls, ['https://only.jpg']);
    });

    test('displayImageUrls: нет картинок', () {
      final p = PostEntity(
        id: '1',
        userId: 'u',
        createdAt: t0,
      );
      expect(p.displayImageUrls, isEmpty);
    });

    test('copyWith clearImage сбрасывает imageUrl и imageUrls', () {
      final p = PostEntity(
        id: '1',
        userId: 'u',
        imageUrl: 'https://x.jpg',
        imageUrls: const ['https://y.jpg'],
        createdAt: t0,
      );
      final cleared = p.copyWith(clearImage: true);
      expect(cleared.imageUrl, '');
      expect(cleared.imageUrls, isEmpty);
    });
  });
}
