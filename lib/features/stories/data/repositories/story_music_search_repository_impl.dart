import '../../domain/entities/story_music_track.dart';
import '../../domain/repositories/story_music_search_repository.dart';
import '../datasources/itunes_music_remote_datasource.dart';

class StoryMusicSearchRepositoryImpl implements StoryMusicSearchRepository {
  StoryMusicSearchRepositoryImpl(this._remote);

  final ItunesMusicRemoteDataSource _remote;

  @override
  Future<List<StoryMusicTrack>> searchTracks(String query) =>
      _remote.search(query);
}
