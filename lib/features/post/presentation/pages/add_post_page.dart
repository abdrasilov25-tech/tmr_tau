import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/repositories/post_repository.dart';

enum _MediaType { photo, video }

class AddPostPage extends StatefulWidget {
  const AddPostPage({super.key});

  @override
  State<AddPostPage> createState() => _AddPostPageState();
}

class _AddPostPageState extends State<AddPostPage> {
  File? _image;
  File? _video;
  final _captionController = TextEditingController();
  bool _loading = false;
  static const int _maxVideoSeconds = 120; // 2 минуты

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _showPickMediaSheet() async {
    final choice = await showModalBottomSheet<_MediaType>(
      context: context,
      backgroundColor: Colors.white,
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
                'Добавить фото или видео',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.black87,
                    ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, size: 28),
                title: const Text('Фото'),
                subtitle: const Text('Галерея или камера'),
                onTap: () => Navigator.pop(context, _MediaType.photo),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, size: 28),
                title: const Text('Видео'),
                subtitle: const Text('До 2 минут'),
                onTap: () => Navigator.pop(context, _MediaType.video),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _MediaType.photo) {
      await _pickImage();
    } else {
      await _pickVideo();
    }
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Откуда взять фото?'),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Галерея'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Камера'),
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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Откуда взять видео?'),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('Галерея'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Камера'),
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
      setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    if (durationSeconds > _maxVideoSeconds) {
      setState(() => _loading = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Видео слишком длинное'),
          content: Text(
            'Ваше видео — ${durationSeconds ~/ 60} мин ${durationSeconds % 60} сек. '
            'Для новостей допускается не более 2 минут.\n\n'
            'Рекомендуем обрезать видео в приложении «Фото» (iPhone) или «Галерея» (Android), '
            'затем снова выберите его здесь.',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _video = file;
      _image = null;
      _loading = false;
    });
  }

  Future<String> _uploadImage(File file) async {
    const uuid = Uuid();
    final ext = file.path.split('.').last;
    final path = '${uuid.v4()}.$ext';
    await Supabase.instance.client.storage
        .from(SupabaseConstants.bucketPosts)
        .upload(path, file, fileOptions: const FileOptions(upsert: true));
    return Supabase.instance.client.storage
        .from(SupabaseConstants.bucketPosts)
        .getPublicUrl(path);
  }

  Future<String> _uploadVideo(File file) async {
    const uuid = Uuid();
    final ext = file.path.split('.').last;
    final path = 'videos/${uuid.v4()}.$ext';
    await Supabase.instance.client.storage
        .from(SupabaseConstants.bucketPosts)
        .upload(path, file, fileOptions: const FileOptions(upsert: true));
    return Supabase.instance.client.storage
        .from(SupabaseConstants.bucketPosts)
        .getPublicUrl(path);
  }

  Future<void> _publish() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите в аккаунт')),
      );
      return;
    }
    if (_image == null && _video == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте фото или видео')),
      );
      return;
    }

    final postRepository = context.read<PostRepository>();
    final userId = authState.user.id;
    final caption = _captionController.text.trim();

    setState(() => _loading = true);
    try {
      String imageUrl = '';
      String? videoUrl;
      int videoDurationSeconds = 0;

      if (_image != null) {
        imageUrl = await _uploadImage(_image!);
      } else if (_video != null) {
        videoUrl = await _uploadVideo(_video!);
        final controller = VideoPlayerController.file(_video!);
        await controller.initialize();
        videoDurationSeconds = controller.value.duration.inSeconds;
        await controller.dispose();
      }

      await postRepository.createPost(
        userId: userId,
        imageUrl: imageUrl,
        caption: caption,
        videoUrl: videoUrl,
        videoDurationSeconds: videoDurationSeconds,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новость опубликована')),
      );
      context.go('/home/news');
    } catch (e, st) {
      if (!mounted) return;
      String message = 'Ошибка при публикации';
      if (e is StorageException) {
        message = 'Storage: создайте бакет «posts» в Supabase и добавьте политики загрузки (см. docs/SUPABASE_SETUP.md)';
      } else if (e is PostgrestException) {
        message = 'База данных: проверьте таблицу posts и выполните schema.sql в Supabase';
      } else {
        message = 'Ошибка: $e';
      }
      debugPrint('AddPost error: $e $st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _hasMedia => _image != null || _video != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Новая новость',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _loading || !_hasMedia ? null : _publish,
            child: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Опубликовать',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GestureDetector(
            onTap: _loading ? null : _showPickMediaSheet,
            child: Container(
              height: 320,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: _image != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _image!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  : _video != null
                      ? Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _VideoPreview(file: _video!),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam, color: Colors.white, size: 20),
                                  SizedBox(width: 6),
                                  Text('Видео до 2 мин', style: TextStyle(color: Colors.white, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 64,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Фото или видео до 2 мин',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Нажмите, чтобы выбрать',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _captionController,
            decoration: InputDecoration(
              hintText: 'Что происходит в Темиртау?',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              border: InputBorder.none,
              filled: false,
            ),
            maxLines: 4,
            style: const TextStyle(fontSize: 16),
          ),
        ],
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
      return const Center(child: CircularProgressIndicator());
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
