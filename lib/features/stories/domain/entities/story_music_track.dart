import 'package:equatable/equatable.dart';

/// Выбранный трек для стикера «Музыка» в сторис (метаданные + URL превью).
class StoryMusicTrack extends Equatable {
  const StoryMusicTrack({
    required this.title,
    required this.artist,
    required this.previewUrl,
    this.artworkUrl,
  });

  final String title;
  final String artist;
  /// HTTPS URL короткого превью (например iTunes preview).
  final String previewUrl;
  final String? artworkUrl;

  @override
  List<Object?> get props => [title, artist, previewUrl, artworkUrl];
}
