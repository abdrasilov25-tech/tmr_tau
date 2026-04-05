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
import '../../../../core/router/go_router_pop_safe.dart';
import '../../domain/repositories/stories_repository.dart';
import '../utils/story_media_permissions.dart';

/// Единый формат сторис 9:16 (как в Instagram).
const double _storyAspectRatio = 9 / 16;
enum _CreateMode { publication, story, video, live }

class AddStoryPage extends StatefulWidget {
  const AddStoryPage({
    super.key,
    this.isVideoMode = false,
    this.preloadedFile,
  });

  final bool isVideoMode;
  /// Файл, уже захваченный StoryCameraPage (пропускаем авто-открытие галереи).
  final File? preloadedFile;

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
  bool _autoGalleryOpened = false;
  late _CreateMode _activeMode;

  bool get _isVideoMode => _activeMode == _CreateMode.video;
  bool get _isLiveMode => _activeMode == _CreateMode.live;

  bool get _hasMedia => _image != null || _video != null;

  Future<bool> _ensureGalleryAccess({required bool forVideo}) async {
    final access =
        await StoryMediaPermissions.galleryAccess(forVideo: forVideo);
    switch (access) {
      case StoryGalleryAccess.ok:
        return true;
      case StoryGalleryAccess.deniedInDialog:
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Нужен доступ к галерее. Нажмите «Разрешить» в запросе системы '
                'или откройте галерею ещё раз.',
              ),
            ),
          );
        }
        return false;
      case StoryGalleryAccess.needsSettings:
        if (mounted) {
          await StoryMediaPermissions.offerOpenSettings(
            context,
            message:
                'Доступ к фото и медиатеке для Tmr Tau отключён. '
                'Включите его в настройках приложения (Фото / Медиа).',
          );
        }
        return false;
    }
  }


  @override
  void initState() {
    super.initState();
    _activeMode = widget.isVideoMode ? _CreateMode.video : _CreateMode.story;

    // Если файл пришёл с StoryCameraPage — загружаем сразу
    final preloaded = widget.preloadedFile;
    if (preloaded != null) {
      _autoGalleryOpened = true; // Не открываем галерею
      if (widget.isVideoMode) {
        _video = preloaded;
        _validatePreloadedVideo(preloaded);
      } else {
        _image = preloaded;
      }
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openGalleryOnEnter();
      });
    }
  }

  Future<void> _validatePreloadedVideo(File file) async {
    setState(() => _loading = true);
    try {
      final ctrl = VideoPlayerController.file(file);
      await ctrl.initialize();
      final seconds = ctrl.value.duration.inSeconds;
      await ctrl.dispose();
      if (!mounted) return;
      if (seconds > _maxVideoSeconds) {
        setState(() {
          _video = null;
          _loading = false;
        });
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.grey.shade900,
            title: const Text('Видео слишком длинное',
                style: TextStyle(color: Colors.white)),
            content: Text(
              'Длительность — ${seconds ~/ 60} мин ${seconds % 60} сек. '
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
      } else {
        setState(() {
          _videoDurationSeconds = seconds;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _openGalleryOnEnter() async {
    if (_autoGalleryOpened) return;
    if (_isLiveMode) return;
    // Флаг после попытки: при отказе не крутим picker повторно сами, но и не блокируем ручной выбор.
    _autoGalleryOpened = true;
    if (_isVideoMode) {
      await _pickVideoFromSource(ImageSource.gallery);
      return;
    }
    await _pickImageFromSource(ImageSource.gallery);
  }

  void _setMode(_CreateMode mode) {
    if (_activeMode == mode) return;
    setState(() {
      _activeMode = mode;
      if (_activeMode == _CreateMode.live) {
        _image = null;
        _video = null;
        _videoDurationSeconds = 0;
      }
    });
    if (!_isLiveMode && !_hasMedia) {
      _autoGalleryOpened = false;
      Future<void>.microtask(_openGalleryOnEnter);
    }
  }

  Future<void> _pickSource() async {
    if (_isLiveMode) return;
    if (_isVideoMode) {
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
    await _pickImageFromSource(source);
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    if (source == ImageSource.gallery) {
      final ok = await _ensureGalleryAccess(forVideo: false);
      if (!ok || !mounted) return;
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery);
      if (x != null && mounted) {
        setState(() {
          _image = File(x.path);
          _video = null;
        });
      }
    } else {
      // Открываем StoryCameraPage — hold-to-record UX
      if (!mounted) return;
      context.push('/story-camera');
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
    await _pickVideoFromSource(source);
  }

  Future<void> _pickVideoFromSource(ImageSource source) async {
    if (source == ImageSource.camera) {
      // Открываем StoryCameraPage — hold-to-record UX
      if (!mounted) return;
      context.push('/story-camera');
      return;
    }
    final ok = await _ensureGalleryAccess(forVideo: true);
    if (!ok || !mounted) return;
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
    if (_isLiveMode) {
      if (!mounted) return;
      context.push('/live/host');
      return;
    }
    if (!_hasMedia) return;
    final authState = context.read<AuthBloc>().state;
    final postRepository = context.read<PostRepository>();
    final storiesRepository = context.read<StoriesRepository>();
    if (authState is! AuthAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Войдите, чтобы добавить историю')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final pickedImage = _image;
      final pickedVideo = _video;
      if (pickedImage == null && pickedVideo == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      const uuid = Uuid();
      String imageUrl = '';
      String? videoUrl;
      if (pickedImage != null) {
        final ext = pickedImage.path.split('.').last;
        final path = '${uuid.v4()}.$ext';
        await Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .upload(path, pickedImage, fileOptions: const FileOptions(upsert: true));
        imageUrl = Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .getPublicUrl(path);
      }
      if (pickedVideo != null) {
        final ext = pickedVideo.path.split('.').last;
        final path = '${uuid.v4()}.$ext';
        await Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .upload(path, pickedVideo, fileOptions: const FileOptions(upsert: true));
        videoUrl = Supabase.instance.client.storage
            .from(SupabaseConstants.bucketStories)
            .getPublicUrl(path);
        // Для видео-сторис без отдельного превью используем videoUrl как imageUrl
        if (imageUrl.isEmpty) imageUrl = videoUrl;
      }

      if (_activeMode == _CreateMode.publication) {
        await postRepository.createPost(
              userId: authState.user.id,
              imageUrl: imageUrl,
              caption: _captionController.text.trim(),
              videoUrl: videoUrl,
              videoDurationSeconds: _videoDurationSeconds,
              kind: 'publication',
            );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Публикация добавлена')),
        );
        context.popOrGoHomeFeed(true);
        return;
      }

      bool alsoToProfile = false;
      if (_isVideoMode && _video != null && mounted) {
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

      if (!mounted) return;
      await storiesRepository.addStory(
            userId: authState.user.id,
            imageUrl: imageUrl,
            videoUrl: videoUrl,
            caption: _captionController.text.trim().isEmpty ? null : _captionController.text.trim(),
          );
      if (!mounted) return;

      if (alsoToProfile && videoUrl != null && mounted) {
        await postRepository.createPost(
              userId: authState.user.id,
              videoUrl: videoUrl,
              videoDurationSeconds: _videoDurationSeconds,
              kind: 'publication',
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('История добавлена')),
      );
      context.popOrGoHomeFeed(true);
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
    final emptyState = _isLiveMode
        ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 640),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 14 * (1 - t)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1E1E26).withValues(alpha: 0.94),
                            const Color(0xFF14141A).withValues(alpha: 0.98),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF3355).withValues(alpha: 0.12),
                            blurRadius: 28,
                            spreadRadius: 0,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.wifi_tethering_rounded,
                              size: 56,
                              color: const Color(0xFFFF5A73),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Запуск прямого эфира',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: const Color(0xFFF2F2F7),
                                    fontWeight: FontWeight.w700,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Откроется экран вещателя: камера, название и выход в эфир.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.58),
                                height: 1.4,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 26),
                            FilledButton.icon(
                              onPressed: _publish,
                              icon: const Icon(Icons.live_tv_rounded),
                              label: const Text('Начать эфир'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF3355),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isVideoMode
                    ? Icons.videocam_outlined
                    : (_activeMode == _CreateMode.publication
                        ? Icons.photo_library_outlined
                        : Icons.auto_awesome_rounded),
                size: 80,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 16),
              Text(
                _isVideoMode
                    ? 'Добавьте видео (до 2 мин)'
                    : (_activeMode == _CreateMode.publication
                        ? 'Выберите фото/видео для публикации'
                        : 'Для выкладывания историй'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white70,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _pickSource,
                icon: Icon(
                  _isVideoMode ? Icons.videocam_outlined : Icons.add_photo_alternate_outlined,
                ),
                label: Text(_isVideoMode ? 'Выбрать видео' : 'Выбрать фото'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          );
    final mediaState = Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _storyAspectRatio,
              child: ClipRect(
                child: _video != null
                    ? _VideoPreview(file: _video!)
                    : (_image != null
                        ? Image.file(
                            _image!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          )
                        : ColoredBox(
                            color: Colors.grey.shade900,
                            child: Center(
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: Colors.grey.shade500,
                                size: 44,
                              ),
                            ),
                          )),
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
                  color: Colors.black.withValues(alpha: 0.2),
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
                  _isVideoMode ? 'Другое видео' : 'Другое фото',
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
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.popOrGoHomeFeed(),
        ),
        title: Text(
          _isLiveMode
              ? 'Прямой эфир'
              : (_isVideoMode ? 'Видео' : (_activeMode == _CreateMode.publication ? 'Публикация' : 'Сторис')),
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
          child: _hasMedia ? mediaState : emptyState,
        ),
      ),
      bottomNavigationBar: _CreationModeBar(
        activeMode: _activeMode,
        onModeChanged: _setMode,
      ),
    );
  }
}

class _CreationModeBar extends StatelessWidget {
  const _CreationModeBar({
    required this.activeMode,
    required this.onModeChanged,
  });

  final _CreateMode activeMode;
  final ValueChanged<_CreateMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    Widget modeChip({
      required String label,
      required bool active,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : Colors.white70,
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth - 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    modeChip(
                      label: 'Публикация',
                      active: activeMode == _CreateMode.publication,
                      onTap: () => onModeChanged(_CreateMode.publication),
                    ),
                    modeChip(
                      label: 'История',
                      active: activeMode == _CreateMode.story,
                      onTap: () => onModeChanged(_CreateMode.story),
                    ),
                    modeChip(
                      label: 'Видео',
                      active: activeMode == _CreateMode.video,
                      onTap: () => onModeChanged(_CreateMode.video),
                    ),
                    modeChip(
                      label: 'Прямой эфир',
                      active: activeMode == _CreateMode.live,
                      onTap: () => onModeChanged(_CreateMode.live),
                    ),
                  ],
                ),
              ),
            );
          },
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
    final size = _controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return SizedBox.expand(
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      ),
    );
  }
}
