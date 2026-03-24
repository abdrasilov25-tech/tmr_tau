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
  const AddPostPage({
    super.key,
    this.kind = 'news',
    this.initialVideoMode = false,
  });

  final String kind;
  final bool initialVideoMode;

  @override
  State<AddPostPage> createState() => _AddPostPageState();
}

class _AddPostPageState extends State<AddPostPage> {
  File? _image;
  File? _video;
  final _captionController = TextEditingController();
  bool _loading = false;
  static const int _maxVideoSeconds = 120; // 2 минуты

  bool get _isPublication => widget.kind == 'publication';
  String get _pageTitle => _isPublication ? 'Новая публикация' : 'Новая новость';
  String get _successMessage =>
      _isPublication ? 'Публикация опубликована' : 'Новость опубликована';
  String get _captionHint =>
      _isPublication ? 'Поделитесь моментом из жизни...' : 'Что происходит в Темиртау?';

  @override
  void initState() {
    super.initState();
    if (widget.initialVideoMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _pickVideo();
      });
    }
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
            'Допускается не более 2 минут.\n\n'
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

      final createdPost = await postRepository.createPost(
        userId: userId,
        imageUrl: imageUrl,
        caption: caption,
        videoUrl: videoUrl,
        videoDurationSeconds: videoDurationSeconds,
        kind: widget.kind,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_successMessage)),
      );
      if (_isPublication) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop(createdPost);
          return;
        }
        context.go('/home/feed');
      } else {
        context.go('/home/news');
      }
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: cs.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _pageTitle,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: cs.onSurface,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _loading || !_hasMedia ? null : _publish,
              style: FilledButton.styleFrom(
                elevation: 0,
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _loading
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.onPrimary,
                      ),
                    )
                  : const Text(
                      'Опубликовать',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFE8EEF4),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            GestureDetector(
              onTap: _loading ? null : _showPickMediaSheet,
              child: _MediaPickerCard(
                loading: _loading,
                image: _image,
                video: _video,
              ),
            ),
            const SizedBox(height: 18),
            _CaptionField(
              controller: _captionController,
              hintText: _captionHint,
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка выбора медиа — светлый стиль для новостей и публикаций.
class _MediaPickerCard extends StatelessWidget {
  const _MediaPickerCard({
    required this.loading,
    required this.image,
    required this.video,
  });

  final bool loading;
  final File? image;
  final File? video;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      height: 340,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: image != null
            ? Image.file(
                image!,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              )
            : video != null
                ? Stack(
                    alignment: Alignment.center,
                    fit: StackFit.expand,
                    children: [
                      _VideoPreview(file: video!),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.videocam_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Видео до 2 мин',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : _LightEmptyMediaPlaceholder(
                    loading: loading,
                    colorScheme: cs,
                    theme: theme,
                  ),
      ),
    );
  }
}

class _LightEmptyMediaPlaceholder extends StatelessWidget {
  const _LightEmptyMediaPlaceholder({
    required this.loading,
    required this.colorScheme,
    required this.theme,
  });

  final bool loading;
  final ColorScheme colorScheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary.withValues(alpha: 0.08),
            const Color(0xFFF8FAFC),
            colorScheme.primary.withValues(alpha: 0.05),
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(
              Icons.add_photo_alternate_rounded,
              size: 48,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              'Фото или видео до 2 минут',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              loading
                  ? 'Подождите...'
                  : 'Нажмите здесь — откроется выбор из галереи или камеры',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF64748B),
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptionField extends StatelessWidget {
  const _CaptionField({
    required this.controller,
    required this.hintText,
  });

  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFCBD5E1)),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextField(
        controller: controller,
        maxLines: 5,
        style: TextStyle(
          color: const Color(0xFF0F172A),
          fontSize: 16,
          height: 1.45,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: TextStyle(
            color: const Color(0xFF94A3B8),
            fontSize: 16,
            height: 1.45,
            fontWeight: FontWeight.w400,
          ),
          border: InputBorder.none,
          isDense: true,
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
