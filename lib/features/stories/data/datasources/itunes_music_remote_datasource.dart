import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/story_music_track.dart';

/// Поиск треков через публичный iTunes Search API (превью ~30 с), без ключей.
class ItunesMusicRemoteDataSource {
  ItunesMusicRemoteDataSource({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  Future<List<StoryMusicTrack>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': q,
      'media': 'music',
      'limit': '35',
    });

    final res = await _client.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'TmrTauStories/1.0',
      },
    );

    if (res.statusCode != 200) return const [];

    final map = jsonDecode(res.body) as Map<String, dynamic>;
    final list = map['results'] as List<dynamic>? ?? const [];

    final out = <StoryMusicTrack>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final preview = item['previewUrl'] as String?;
      if (preview == null || preview.isEmpty) continue;
      out.add(
        StoryMusicTrack(
          title: item['trackName'] as String? ?? 'Трек',
          artist: item['artistName'] as String? ?? '',
          previewUrl: preview,
          artworkUrl: item['artworkUrl60'] as String? ??
              item['artworkUrl100'] as String?,
        ),
      );
    }
    return out;
  }
}
