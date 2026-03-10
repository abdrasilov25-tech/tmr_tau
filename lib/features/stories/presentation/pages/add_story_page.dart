import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/repositories/stories_repository.dart';

/// Единый формат сторис 9:16 (как в Instagram).
const double _storyAspectRatio = 9 / 16;

class AddStoryPage extends StatefulWidget {
  const AddStoryPage({super.key, this.isVideoMode = false});

  final bool isVideoMode;

  @override
  State<AddStoryPage> createState() => _AddStoryPageState();
}

class _AddStoryPageState extends State<AddStoryPage> {
  File? _image;
  File? _video;
  int _videoDurationSeconds = 0;
  bool _loading = false;
  final _captionController = TextEditingController();
  static const int _maxVideoSeconds = 120;

  bool get _hasMedia => _image != null || _video != null;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    if (widget.isVideoMode) {
      await _pickVideo();
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Сторис',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined,
                    color: Colors.white, size: 28),
                title: const Text('Галерея', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined,
                    color: Colors.white, size: 28),
                title: const Text('Камера', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source);
    if (x != null && mounted) {
      setState(() {
        _image = File(x.path);
        _video = null;
      });
    }
  }

  Future<void> _pickVideo() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Видео',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Не более 2 минут',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.video_library_outlined,
                    color: Colors.white, size: 28),
                title: const Text('Галерея', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined,
                    color: Colors.white, size: 28),
                title: const Text('Камера', style: TextStyle(color: Colors.white)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final x = await picker.pickVideo(source: source);
    if (x == null || !mounted) return;
    final file = File(x.path);
    setState(() => _loading = true);
    int durationSeconds = 0;
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      durationSeconds = controller.value.duration.inSeconds;
      await controller.dispose();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось определить длительность видео')),
        );
      }
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    if (durationSeconds > _maxVideoSeconds) {
      setState(() => _loading = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: const Text('Видео слишком длинное', style: TextStyle(color: Colors.white)),
          content: Text(
            'Длительность — ${durationSeconds ~/ 60} мин ${durationSeconds % 60} сек. '
            'Для историй допускается не более 2 минут.',
            style: TextStyle(color: Colors.grey.shade300, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
      return;
    }
    if (mounted) {
      setState(() {
      _video = file;
      _videoDurationSeconds = durationSeconds;
      _image = null;
      _loading = false;
    });
    }
  }

  Future<void> _publish() async {
    if (!_hasMedia) return;
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы добавить историю')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      const uuid = Uuid();
      String imageUrl = '';
      String? videoUrl;
      if (_image != null) {
        final ext = _image!.path.split('.').last;
        final path = '${uuid.v4()}.$ext';
        await Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .upload(path, _image!, fileOptions: const FileOptions(upsert: true));
        imageUrl = Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .getPublicUrl(path);
      }
      if (_video != null) {
        final ext = _video!.path.split('.').last;
        final path = '${uuid.v4()}.$ext';
        await Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .upload(path, _video!, fileOptions: const FileOptions(upsert: true));
        videoUrl = Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .getPublicUrl(path);
      }

      bool alsoToProfile = false;
      if (widget.isVideoMode && _video != null && mounted) {
        final choice = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (ctx) => Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Куда опубликовать?',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: const Icon(Icons.auto_awesome, color: Colors.white),
                      title: const Text('Только сторис (24 ч)', style: TextStyle(color: Colors.white)),
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                    ListTile(
                      leading: const Icon(Icons.person, color: Colors.white),
                      title: const Text('Сторис и в профиль', style: TextStyle(color: Colors.white)),
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        alsoToProfile = choice == true;
      }

      await context.read<StoriesRepository>().addStory(
            userId: authState.user.id,
            imageUrl: imageUrl,
            videoUrl: videoUrl,
            caption: _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
          );

      if (alsoToProfile && videoUrl != null && mounted) {
        await context.read<PostRepository>().createPost(
              userId: authState.user.id,
              videoUrl: videoUrl,
              videoDurationSeconds: _videoDurationSeconds,
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История добавлена')),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      String message = 'Ошибка: $e';
      if (e is StorageException) {
        message =
            'Создайте бакет «stories» в Supabase Storage и настройте политики загрузки';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.isVideoMode ? 'Видео' : 'Сторис',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          if (_hasMedia)
            TextButton(
              onPressed: _loading ? null : _publish,
              child: _loading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Опубликовать',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: !_hasMedia
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.isVideoMode
                          ? Icons.videocam_outlined
                          : Icons.auto_awesome_rounded,
                      size: 80,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.isVideoMode
                          ? 'Добавьте видео в историю (до 2 мин)'
                          : 'Для выкладывания историй',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white70,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _pickSource,
                      icon: Icon(widget.isVideoMode
                          ? Icons.videocam_outlined
                          : Icons.add_photo_alternate_outlined),
                      label: Text(widget.isVideoMode ? 'Выбрать видео' : 'Выбрать фото'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _storyAspectRatio,
                          child: ClipRect(
                            child: _video != null
                                ? _VideoPreview(file: _video!)
                                : Image.file(
                                    _image!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade400),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _captionController,
                          style: const TextStyle(color: Colors.black87, fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: 'Добавить подпись...',
                            hintStyle: TextStyle(color: Colors.black45),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                          maxLines: 2,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _pickSource,
                            icon: const Icon(Icons.refresh, color: Colors.white),
                            label: Text(
                              widget.isVideoMode ? 'Другое видео' : 'Другое фото',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _publish,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(_loading ? 'Публикация...' : 'Опубликовать'),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  const _VideoPreview({required this.file});

  final File file;

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) setState(() {});
        _controller.setLooping(true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: _controller.value.size.width,
        height: _controller.value.size.height,
        child: VideoPlayer(_controller),
      ),
    );
  }
}
