import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_trimmer/video_trimmer.dart';

/// Экран обрезки видео под лимит длительности (новость / публикация).
/// Возвращает [File] обрезанного ролика или `null`, если пользователь вышел без сохранения.
class VideoTrimPage extends StatefulWidget {
  const VideoTrimPage({
    super.key,
    required this.sourceFile,
    required this.maxDurationSeconds,
    required this.contextLabel,
  });

  final File sourceFile;
  final int maxDurationSeconds;
  /// Родительный падеж после «для»: `новости`, `публикации`.
  final String contextLabel;

  @override
  State<VideoTrimPage> createState() => _VideoTrimPageState();
}

class _VideoTrimPageState extends State<VideoTrimPage> {
  final Trimmer _trimmer = Trimmer();

  double _startValue = 0;
  double _endValue = 0;
  bool _playing = false;
  bool _loadingVideo = true;
  bool _saving = false;

  Future<void> _load() async {
    await _trimmer.loadVideo(videoFile: widget.sourceFile);
    if (mounted) setState(() => _loadingVideo = false);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _trimmer.videoPlayerController?.dispose();
    _trimmer.dispose();
    super.dispose();
  }

  Duration get _maxLen => Duration(seconds: widget.maxDurationSeconds);

  DurationStyle get _durationStyle =>
      widget.maxDurationSeconds >= 3600
          ? DurationStyle.FORMAT_HH_MM_SS
          : DurationStyle.FORMAT_MM_SS;

  Future<void> _save() async {
    if (_saving) return;
    if (_endValue <= _startValue) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите корректный фрагмент')),
        );
      }
      return;
    }
    setState(() => _saving = true);
    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _startValue,
        endValue: _endValue,
        storageDir: StorageDir.temporaryDirectory,
        videoFolderName: 'tmr_tau_trim',
        onSave: (path) {
          if (!mounted) return;
          if (path == null || path.isEmpty) {
            setState(() => _saving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Не удалось сохранить видео. Попробуйте ещё раз.'),
              ),
            );
            return;
          }
          Navigator.of(context).pop<File>(File(path));
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка при обрезке видео')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxMin = widget.maxDurationSeconds ~/ 60;
    final maxSec = widget.maxDurationSeconds % 60;
    final limitText = maxSec == 0 ? '$maxMin мин' : '$maxMin мин $maxSec сек';

    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('Обрезка видео'),
          actions: [
            TextButton(
              onPressed: _saving || _loadingVideo ? null : _save,
              child: Text(
                'Готово',
                style: TextStyle(
                  color: _saving || _loadingVideo ? Colors.white38 : Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        body: _loadingVideo
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
                children: [
                  if (_saving)
                    const LinearProgressIndicator(
                      backgroundColor: Colors.black,
                      color: Colors.white,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      'Выберите фрагмент до $limitText для ${widget.contextLabel}. '
                      'Перемещайте маркеры на шкале времени.',
                      style: const TextStyle(color: Colors.white70, height: 1.35),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(child: VideoViewer(trimmer: _trimmer)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TrimViewer(
                      trimmer: _trimmer,
                      viewerHeight: 52,
                      viewerWidth: MediaQuery.sizeOf(context).width,
                      type: ViewerType.auto,
                      maxVideoLength: _maxLen,
                      durationStyle: _durationStyle,
                      editorProperties: TrimEditorProperties(
                        borderPaintColor: Colors.amber,
                        borderWidth: 3,
                        borderRadius: 6,
                        circlePaintColor: Colors.amber.shade800,
                      ),
                      areaProperties: TrimAreaProperties.edgeBlur(
                        thumbnailQuality: 50,
                      ),
                      onChangeStart: (v) => _startValue = v,
                      onChangeEnd: (v) => _endValue = v,
                      onChangePlaybackState: (v) =>
                          setState(() => _playing = v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24, top: 8),
                    child: IconButton(
                      iconSize: 72,
                      color: Colors.white,
                      onPressed: _saving || _loadingVideo
                          ? null
                          : () async {
                              final playing = await _trimmer.videoPlaybackControl(
                                startValue: _startValue,
                                endValue: _endValue,
                              );
                              if (mounted) setState(() => _playing = playing);
                            },
                      icon: Icon(
                        _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
