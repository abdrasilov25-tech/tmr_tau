import '../entities/story_music_track.dart';

abstract class StoryMusicSearchRepository {
  Future<List<StoryMusicTrack>> searchTracks(String query);
}
