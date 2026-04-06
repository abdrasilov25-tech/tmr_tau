import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/story_music_track.dart';
import '../../domain/repositories/story_music_search_repository.dart';

/// Полноэкранный выбор музыки для сторис.
///
/// [rootNavigator: true] — результат `pop` доходит до `await showStoryMusicPicker` с GoRouter.
/// Все действия — через [GestureDetector], без [IconButton]/[InkWell]/[Tooltip], чтобы не ловить M3 ArgumentError «8.0».
Future<StoryMusicTrack?> showStoryMusicPicker(
  BuildContext context, {
  required StoryMusicSearchRepository repository,
  bool rootNavigator = true,
}) {
  final nav = Navigator.of(context, rootNavigator: rootNavigator);
  return nav.push<StoryMusicTrack?>(
    MaterialPageRoute<StoryMusicTrack?>(
      fullscreenDialog: true,
      builder: (ctx) => _StoryMusicPickerScaffold(
        repository: repository,
        navigator: nav,
      ),
    ),
  );
}

class _StoryMusicPickerScaffold extends StatefulWidget {
  const _StoryMusicPickerScaffold({
    required this.repository,
    required this.navigator,
  });

  final StoryMusicSearchRepository repository;
  final NavigatorState navigator;

  @override
  State<_StoryMusicPickerScaffold> createState() =>
      _StoryMusicPickerScaffoldState();
}

class _StoryMusicPickerScaffoldState extends State<_StoryMusicPickerScaffold> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _player = AudioPlayer();
  Timer? _debounce;
  List<StoryMusicTrack> _results = [];
  StoryMusicTrack? _selected;
  StoryMusicTrack? _playing;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final list = await widget.repository.searchTracks('hits 2024');
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_player.dispose());
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 380), () {
      unawaited(_runSearch(value));
    });
  }

  Future<void> _runSearch(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) {
      await _bootstrap();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.searchTracks(q);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _togglePreview(StoryMusicTrack t) async {
    if (_playing?.previewUrl == t.previewUrl) {
      await _player.pause();
      if (!mounted) return;
      setState(() => _playing = null);
      return;
    }
    setState(() {
      _selected = t;
      _playing = t;
    });
    try {
      await _player.stop();
      await _player.play(UrlSource(t.previewUrl));
    } catch (e) {
      if (!mounted) return;
      setState(() => _playing = null);
    }
  }

  /// Без setState перед pop: иначе rebuild во время закрытия маршрута; плеер глушим до pop.
  Future<void> _confirmTrack(StoryMusicTrack t) async {
    try {
      await _player.stop();
    } catch (e) { debugPrint('$e'); }
    if (!mounted) return;
    widget.navigator.pop(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(
                children: [
                  _TapCell(
                    onTap: () => widget.navigator.pop(),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                  ),
                  const Expanded(
                    child: Text(
                      'Музыка',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _TapCell(
                    onTap: _selected == null ? null : () => widget.navigator.pop(_selected),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                      child: Text(
                        'Готово',
                        style: TextStyle(
                          color: _selected == null
                              ? Colors.white38
                              : const Color(0xFF0095F6),
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                focusNode: _focus,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                cursorColor: Colors.white,
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  filled: true,
                  fillColor: Colors.white12,
                  prefixIcon:
                      const Icon(Icons.search_rounded, color: Colors.white54),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (v) => unawaited(_runSearch(v)),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Разделы',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _GenreChip(
                          label: 'Поп',
                          icon: Icons.star_rounded,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B9D),
                              Color(0xFFC44569),
                            ],
                          ),
                          onTap: () => _searchAndFocus('pop hits'),
                        ),
                        _GenreChip(
                          label: 'Рэп',
                          icon: Icons.mic_rounded,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFFA726),
                              Color(0xFFE65100),
                            ],
                          ),
                          onTap: () => _searchAndFocus('hip hop'),
                        ),
                        _GenreChip(
                          label: 'Казахстан',
                          icon: Icons.public_rounded,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF26C6DA),
                              Color(0xFF00838F),
                            ],
                          ),
                          onTap: () => _searchAndFocus('kazakh pop'),
                        ),
                        _GenreChip(
                          label: 'Ретро',
                          icon: Icons.album_rounded,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF9575CD),
                              Color(0xFF5E35B1),
                            ],
                          ),
                          onTap: () => _searchAndFocus('80s hits'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Expanded(
              child: _loading && _results.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white54),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: _results.length,
                      itemBuilder: (context, i) {
                        final t = _results[i];
                        final sel = _selected?.previewUrl == t.previewUrl;
                        final isPlaying = _playing?.previewUrl == t.previewUrl;
                        final cover = ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: (t.artworkUrl != null &&
                                    t.artworkUrl!.isNotEmpty)
                                ? CachedNetworkImage(
                                    imageUrl: t.artworkUrl!,
                                    fit: BoxFit.cover,
                                    placeholder: (context, progress) =>
                                        Container(color: Colors.white12),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                      color: Colors.white12,
                                      child: const Icon(
                                        Icons.album_rounded,
                                        color: Colors.white38,
                                      ),
                                    ),
                                  )
                                : ColoredBox(
                                    color: Colors.white12,
                                    child: Icon(
                                      Icons.music_note_rounded,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                          ),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 4,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: _TapCell(
                                  onTap: () => unawaited(_togglePreview(t)),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        cover,
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                t.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Text(
                                                t.artist,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Colors.grey.shade400,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _TapCell(
                                onTap: () => unawaited(_togglePreview(t)),
                                child: Icon(
                                  isPlaying
                                      ? Icons.pause_circle_filled_rounded
                                      : Icons.play_circle_fill_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              _TapCell(
                                onTap: () => unawaited(_confirmTrack(t)),
                                child: Icon(
                                  Icons.check_circle_rounded,
                                  color: sel
                                      ? const Color(0xFF0095F6)
                                      : Colors.white38,
                                  size: 30,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _searchAndFocus(String q) {
    _search.text = q;
    unawaited(_runSearch(q));
    _focus.requestFocus();
  }
}

/// Минимальная зона нажатия 48×48, только [GestureDetector] — без Material3-кнопок.
class _TapCell extends StatelessWidget {
  const _TapCell({
    required this.onTap,
    required this.child,
  });

  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final box = ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 48,
        minHeight: 48,
      ),
      child: Center(child: child),
    );
    if (onTap == null) {
      return box;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: box,
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 2),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
