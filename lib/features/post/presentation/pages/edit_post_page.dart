import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';

enum _MediaType { photo, video }

class EditPostPage extends StatefulWidget {
  const EditPostPage({super.key, required this.post});

  final PostEntity post;

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  late final TextEditingController _captionController;
  File? _newImage;
  File? _newVideo;
  bool _loading = false;
  static const int _maxVideoSeconds = 120;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.post.caption);
  }

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
                'Заменить на фото или видео',
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
        _newImage = File(x.path);
        _newVideo = null;
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
            'Для новостей допускается не более 2 минут.',
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
      _newVideo = file;
      _newImage = null;
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

  Future<void> _save() async {
    final caption = _captionController.text.trim();
    setState(() => _loading = true);
    try {
      final repo = context.read<PostRepository>();
      String? newImageUrl;
      String? newVideoUrl;
      int? newVideoDurationSeconds;

      if (_newImage != null) {
        newImageUrl = await _uploadImage(_newImage!);
      } else if (_newVideo != null) {
        newVideoUrl = await _uploadVideo(_newVideo!);
        final controller = VideoPlayerController.file(_newVideo!);
        await controller.initialize();
        newVideoDurationSeconds = controller.value.duration.inSeconds;
        await controller.dispose();
      }

      await repo.updatePost(
        postId: widget.post.id,
        caption: caption,
        imageUrl: newImageUrl,
        videoUrl: newVideoUrl,
        videoDurationSeconds: newVideoDurationSeconds,
        clearImage: _newVideo != null,
        clearVideo: _newImage != null,
      );

      if (!mounted) return;
      final updatedPost = widget.post.copyWith(
        caption: caption,
        imageUrl: newImageUrl,
        videoUrl: newVideoUrl,
        videoDurationSeconds: newVideoDurationSeconds,
        clearImage: _newVideo != null,
        clearVideo: _newImage != null,
      );
      context.pop(updatedPost);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новость обновлена')),
      );
    } catch (e) {
      if (!mounted) return;
      String message = 'Ошибка: $e';
      if (e is StorageException) {
        message = 'Ошибка загрузки файла. Проверьте настройки Supabase Storage.';
      } else if (e is PostgrestException) {
        message = e.message;
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
    final showImage = _newImage != null ||
        (widget.post.imageUrl.isNotEmpty && _newVideo == null);
    final showVideo = _newVideo != null ||
        (widget.post.videoUrl != null &&
            widget.post.videoUrl!.isNotEmpty &&
            _newImage == null);

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
          'Редактировать новость',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Сохранить',
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: showImage
                        ? _newImage != null
                            ? Image.file(
                                _newImage!,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Image.network(
                                widget.post.imageUrl,
                                width: double.infinity,
                                height: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    size: 48,
                                  ),
                                ),
                              )
                        : showVideo
                            ? _newVideo != null
                                ? _EditVideoPreview(file: _newVideo!)
                                : Container(
                                    color: Colors.grey.shade200,
                                    child: Center(
                                      child: Icon(
                                        Icons.videocam,
                                        size: 48,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  )
                            : const SizedBox.shrink(),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Нажмите, чтобы заменить фото или видео',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
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
              hintText: 'Подпись к новости',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              border: InputBorder.none,
            ),
            maxLines: 4,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _EditVideoPreview extends StatefulWidget {
  const _EditVideoPreview({required this.file});

  final File file;

  @override
  State<_EditVideoPreview> createState() => _EditVideoPreviewState();
}

class _EditVideoPreviewState extends State<_EditVideoPreview> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) {
          setState(() {});
          _controller.setLooping(true);
          _controller.play();
        }
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
