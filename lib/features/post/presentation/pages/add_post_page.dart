import 'dart:io';
import 'dart:math' show min;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../../core/router/go_router_pop_safe.dart';
import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/services/geo_service.dart';
import '../../domain/repositories/post_repository.dart';
import '../widgets/post_photo_gallery.dart';
import 'video_trim_page.dart';

enum _MediaType { photo, video }

enum _NewsPhotoSource { galleryMulti, camera }

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
  final List<File> _images = [];
  File? _video;
  final _captionController = TextEditingController();
  bool _loading = false;
  int _previewPage = 0;

  /// Только для kind == news
  bool _newsAnonymous = false;
  bool _newsAttachLocation = false;
  final _newsLocationLabel = TextEditingController();
  bool _newsHasPoll = false;
  final _newsPollQuestion = TextEditingController();
  late final List<TextEditingController> _newsPollOptions = [
    TextEditingController(),
    TextEditingController(),
  ];

  static const int _maxNewsPhotos = 10;

  /// Публикации — как раньше; новости — до 5 мин, как в Threads.
  static const int _maxVideoSecondsPublication = 120;
  static const int _maxVideoSecondsNews = 300;

  int get _maxVideoSeconds =>
      _isPublication ? _maxVideoSecondsPublication : _maxVideoSecondsNews;

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
    _newsLocationLabel.dispose();
    _newsPollQuestion.dispose();
    for (final c in _newsPollOptions) {
      c.dispose();
    }
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
                subtitle: Text(
                  _isPublication
                      ? 'Галерея или камера'
                      : 'До $_maxNewsPhotos фото: галерея (несколько) или камера',
                ),
                onTap: () => Navigator.pop(context, _MediaType.photo),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, size: 28),
                title: const Text('Видео'),
                subtitle: Text(
                  _isPublication ? 'До 2 минут' : 'До 5 минут (как в Threads)',
                ),
                onTap: () => Navigator.pop(context, _MediaType.video),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _MediaType.photo) {
      if (_isPublication) {
        await _pickPublicationSinglePhoto();
      } else {
        await _pickNewsPhotos();
      }
    } else {
      await _pickVideo();
    }
  }

  Future<void> _pickPublicationSinglePhoto() async {
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
    final x = await picker.pickImage(
      source: source,
      imageQuality: 100,
    );
    if (x != null && mounted) {
      setState(() {
        _images
          ..clear()
          ..add(File(x.path));
        _video = null;
        _previewPage = 0;
      });
    }
  }

  Future<void> _pickNewsPhotos() async {
    final action = await showModalBottomSheet<_NewsPhotoSource>(
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
                'Фото к новости',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black87),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, size: 28),
                title: const Text('Несколько из галереи'),
                subtitle: Text('До $_maxNewsPhotos шт. · можно добавлять частями'),
                onTap: () => Navigator.pop(context, _NewsPhotoSource.galleryMulti),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, size: 28),
                title: const Text('Камера'),
                subtitle: const Text('Одно фото, можно повторить'),
                onTap: () => Navigator.pop(context, _NewsPhotoSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    final picker = ImagePicker();
    if (action == _NewsPhotoSource.galleryMulti) {
      final picked = await picker.pickMultiImage(imageQuality: 100);
      if (!mounted || picked.isEmpty) return;
      final room = _maxNewsPhotos - _images.length;
      if (room <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Уже максимум $_maxNewsPhotos фото'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      final addCount = picked.length > room ? room : picked.length;
      if (picked.length > room && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Добавлено $addCount из ${picked.length} (лимит $_maxNewsPhotos)'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      setState(() {
        _video = null;
        for (var i = 0; i < addCount; i++) {
          _images.add(File(picked[i].path));
        }
        _previewPage = _images.length - 1;
      });
    } else {
      final x = await picker.pickImage(source: ImageSource.camera, imageQuality: 100);
      if (x != null && mounted) {
        if (_images.length >= _maxNewsPhotos) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Уже $_maxNewsPhotos фото — удалите лишние'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        setState(() {
          _video = null;
          _images.add(File(x.path));
          _previewPage = _images.length - 1;
        });
      }
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
    } catch (e) {
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
      final trimmed = await Navigator.of(context).push<File?>(
        MaterialPageRoute<File?>(
          fullscreenDialog: true,
          builder: (context) => VideoTrimPage(
            sourceFile: file,
            maxDurationSeconds: _maxVideoSeconds,
            contextLabel: _isPublication ? 'публикации' : 'новости',
          ),
        ),
      );
      if (!mounted || trimmed == null) return;
      setState(() {
        _video = trimmed;
        _images.clear();
        _previewPage = 0;
      });
      return;
    }
    setState(() {
      _video = file;
      _images.clear();
      _previewPage = 0;
      _loading = false;
    });
  }

  /// Длина ролика в секундах (не меньше 1), или `null` при ошибке.
  Future<int?> _probeVideoDurationSeconds(File file) async {
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      final sec = (controller.value.duration.inMilliseconds / 1000)
          .ceil()
          .clamp(1, 1 << 20);
      await controller.dispose();
      return sec;
    } catch (e) {
      return null;
    }
  }

  /// Добровольная обрезка уже выбранного видео (в пределах лимита и длины файла).
  Future<void> _trimCurrentVideo() async {
    final file = _video;
    if (file == null || !mounted) return;
    setState(() => _loading = true);
    final durationSec = await _probeVideoDurationSeconds(file);
    if (!mounted) return;
    setState(() => _loading = false);
    if (durationSec == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть видео для обрезки')),
        );
      }
      return;
    }
    final maxDurationSeconds = min(_maxVideoSeconds, durationSec);
    final trimmed = await Navigator.of(context).push<File?>(
      MaterialPageRoute<File?>(
        fullscreenDialog: true,
        builder: (context) => VideoTrimPage(
          sourceFile: file,
          maxDurationSeconds: maxDurationSeconds,
          contextLabel: _isPublication ? 'публикации' : 'новости',
        ),
      ),
    );
    if (!mounted || trimmed == null) return;
    setState(() => _video = trimmed);
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
    final caption = _captionController.text.trim();
    if (_isPublication && _images.isEmpty && _video == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавьте фото или видео')),
      );
      return;
    }
    if (!_isPublication &&
        _images.isEmpty &&
        _video == null &&
        caption.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напишите текст или добавьте фото/видео')),
      );
      return;
    }
    if (!_isPublication && _newsHasPoll) {
      final pq = _newsPollQuestion.text.trim();
      final opts = _newsPollOptions
          .map((c) => c.text.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (pq.isEmpty || opts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Опрос: укажите вопрос и минимум 2 варианта'),
          ),
        );
        return;
      }
    }

    final postRepository = context.read<PostRepository>();
    final geoService = context.read<GeoService>();
    final userId = authState.user.id;
    GeoPoint? location;

    setState(() => _loading = true);
    try {
      String imageUrl = '';
      List<String> imageUrls = const [];
      String? videoUrl;
      int videoDurationSeconds = 0;

      if (_images.isNotEmpty) {
        imageUrls = [];
        for (final f in _images) {
          imageUrls.add(await _uploadImage(f));
        }
        imageUrl = imageUrls.first;
      } else if (_video != null) {
        videoUrl = await _uploadVideo(_video!);
        final controller = VideoPlayerController.file(_video!);
        await controller.initialize();
        videoDurationSeconds = controller.value.duration.inSeconds;
        await controller.dispose();
      }
      try {
        if (_isPublication || _newsAttachLocation) {
          location = await geoService.getCurrentLocation();
        }
      } catch (e) {
        location = null;
      }

      String? city;
      if (widget.kind == 'news') {
        final prefs = await SharedPreferences.getInstance();
        city = prefs.getString('news_selected_city');
      }
      final pollOpts = !_isPublication && _newsHasPoll
          ? _newsPollOptions
              .map((c) => c.text.trim())
              .where((s) => s.isNotEmpty)
              .take(8)
              .toList()
          : const <String>[];
      final createdPost = await postRepository.createPost(
        userId: userId,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        caption: caption,
        videoUrl: videoUrl,
        videoDurationSeconds: videoDurationSeconds,
        kind: widget.kind,
        latitude: (!_isPublication && _newsAttachLocation)
            ? location?.latitude
            : (_isPublication ? location?.latitude : null),
        longitude: (!_isPublication && _newsAttachLocation)
            ? location?.longitude
            : (_isPublication ? location?.longitude : null),
        city: city,
        isAnonymous: !_isPublication && _newsAnonymous,
        locationLabel: (!_isPublication && _newsAttachLocation)
            ? (_newsLocationLabel.text.trim().isNotEmpty
                ? _newsLocationLabel.text.trim()
                : null)
            : null,
        pollQuestion:
            !_isPublication && _newsHasPoll && pollOpts.length >= 2
                ? _newsPollQuestion.text.trim()
                : null,
        pollOptions: pollOpts,
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

  bool get _hasMedia => _images.isNotEmpty || _video != null;

  bool get _canPublishNews => _hasMedia || _captionController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor:
          _isPublication ? const Color(0xFFF1F5F9) : const Color(0xFFF4F4F5),
      appBar: AppBar(
        backgroundColor:
            _isPublication ? Colors.white : const Color(0xFFF4F4F5),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.06),
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: cs.onSurface),
          onPressed: () => context.popOrGoHomeFeed(),
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
              onPressed: _loading ||
                      (_isPublication ? !_hasMedia : !_canPublishNews)
                  ? null
                  : _publish,
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
            if (!_isPublication) ...[
              TextField(
                controller: _captionController,
                onChanged: (_) => setState(() {}),
                maxLines: 8,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF0A0A0A),
                ),
                decoration: InputDecoration(
                  hintText: 'О чём хотите рассказать?',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 18,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
            ],
            GestureDetector(
              onTap: _loading ? null : _showPickMediaSheet,
              child: SizedBox(
                height: _isPublication ? 340 : 240,
                child: _MediaPickerCard(
                  cardHeight: _isPublication ? 340 : 240,
                  loading: _loading,
                  images: List<File>.unmodifiable(_images),
                  video: _video,
                  previewPage: _previewPage,
                  onPreviewPageChanged: (i) => setState(() => _previewPage = i),
                  onRemoveImageAt: (i) {
                    setState(() {
                      _images.removeAt(i);
                      _previewPage = _images.isEmpty
                          ? 0
                          : _previewPage.clamp(0, _images.length - 1);
                    });
                  },
                  onImageTapZoom: (i) => openLocalPhotoZoom(context, _images, i),
                  maxVideoBadge: 'Видео до ${_maxVideoSeconds ~/ 60} мин',
                  emptyPrimaryText: _isPublication
                      ? 'Фото (макс. качество) или видео до ${_maxVideoSeconds ~/ 60} мин'
                      : 'Фото или видео — по желанию',
                ),
              ),
            ),
            if (_video != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loading ? null : _trimCurrentVideo,
                  icon: const Icon(Icons.content_cut_outlined, size: 20),
                  label: const Text('Обрезать видео'),
                ),
              ),
            ],
            if (_isPublication) ...[
              const SizedBox(height: 18),
              _CaptionField(
                controller: _captionController,
                hintText: _captionHint,
              ),
            ],
            if (!_isPublication) ...[
              const SizedBox(height: 20),
              _NewsThreadsOptions(
                anonymous: _newsAnonymous,
                onAnonymousChanged: (v) => setState(() => _newsAnonymous = v),
                attachLocation: _newsAttachLocation,
                onAttachLocationChanged: (v) =>
                    setState(() => _newsAttachLocation = v),
                locationLabelController: _newsLocationLabel,
                hasPoll: _newsHasPoll,
                onHasPollChanged: (v) => setState(() => _newsHasPoll = v),
                pollQuestionController: _newsPollQuestion,
                pollOptionControllers: _newsPollOptions,
                onAddPollOption: () {
                  if (_newsPollOptions.length >= 4) return;
                  setState(() => _newsPollOptions.add(TextEditingController()));
                },
                onRemovePollOption: (i) {
                  if (_newsPollOptions.length <= 2) return;
                  setState(() {
                    _newsPollOptions.removeAt(i).dispose();
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Панель опций новости в духе Threads: анонимно, место, опрос.
class _NewsThreadsOptions extends StatelessWidget {
  const _NewsThreadsOptions({
    required this.anonymous,
    required this.onAnonymousChanged,
    required this.attachLocation,
    required this.onAttachLocationChanged,
    required this.locationLabelController,
    required this.hasPoll,
    required this.onHasPollChanged,
    required this.pollQuestionController,
    required this.pollOptionControllers,
    required this.onAddPollOption,
    required this.onRemovePollOption,
  });

  final bool anonymous;
  final ValueChanged<bool> onAnonymousChanged;
  final bool attachLocation;
  final ValueChanged<bool> onAttachLocationChanged;
  final TextEditingController locationLabelController;
  final bool hasPoll;
  final ValueChanged<bool> onHasPollChanged;
  final TextEditingController pollQuestionController;
  final List<TextEditingController> pollOptionControllers;
  final VoidCallback onAddPollOption;
  final ValueChanged<int> onRemovePollOption;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Настройки',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
            color: Colors.grey.shade800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Анонимно'),
          subtitle: const Text(
            'Имя и аватар скрыты для других (аккаунт виден модераторам).',
            style: TextStyle(fontSize: 12),
          ),
          value: anonymous,
          onChanged: onAnonymousChanged,
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Местоположение'),
          subtitle: const Text(
            'Прикрепить координаты и подпись к посту',
            style: TextStyle(fontSize: 12),
          ),
          value: attachLocation,
          onChanged: onAttachLocationChanged,
        ),
        if (attachLocation) ...[
          const SizedBox(height: 6),
          TextField(
            controller: locationLabelController,
            decoration: InputDecoration(
              hintText: 'Подпись: район, заведение, адрес…',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
        ],
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Опрос'),
          subtitle: const Text(
            'До 4 вариантов ответа',
            style: TextStyle(fontSize: 12),
          ),
          value: hasPoll,
          onChanged: onHasPollChanged,
        ),
        if (hasPoll) ...[
          const SizedBox(height: 6),
          TextField(
            controller: pollQuestionController,
            decoration: InputDecoration(
              hintText: 'Вопрос опроса',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < pollOptionControllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: pollOptionControllers[i],
                      decoration: InputDecoration(
                        hintText: 'Вариант ${i + 1}',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),
                  if (pollOptionControllers.length > 2)
                    IconButton(
                      onPressed: () => onRemovePollOption(i),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                ],
              ),
            ),
          if (pollOptionControllers.length < 4)
            TextButton.icon(
              onPressed: onAddPollOption,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Добавить вариант'),
            ),
        ],
      ],
    );
  }
}

/// Карточка выбора медиа — светлый стиль для новостей и публикаций.
class _MediaPickerCard extends StatefulWidget {
  const _MediaPickerCard({
    required this.cardHeight,
    required this.loading,
    required this.images,
    required this.video,
    required this.previewPage,
    required this.onPreviewPageChanged,
    required this.onRemoveImageAt,
    required this.onImageTapZoom,
    required this.maxVideoBadge,
    required this.emptyPrimaryText,
  });

  final double cardHeight;
  final bool loading;
  final List<File> images;
  final File? video;
  final int previewPage;
  final ValueChanged<int> onPreviewPageChanged;
  final ValueChanged<int> onRemoveImageAt;
  final ValueChanged<int> onImageTapZoom;
  final String maxVideoBadge;
  final String emptyPrimaryText;

  @override
  State<_MediaPickerCard> createState() => _MediaPickerCardState();
}

class _MediaPickerCardState extends State<_MediaPickerCard> {
  PageController? _pageController;

  void _recreateController() {
    _pageController?.dispose();
    _pageController = null;
    if (widget.images.isEmpty) return;
    _pageController = PageController(
      initialPage: widget.previewPage.clamp(0, widget.images.length - 1),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.images.isNotEmpty) {
      _pageController = PageController(
        initialPage: widget.previewPage.clamp(0, widget.images.length - 1),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _MediaPickerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.images.isEmpty) {
      _pageController?.dispose();
      _pageController = null;
      return;
    }
    if (_pageController == null) {
      _recreateController();
      return;
    }
    if (oldWidget.images.length != widget.images.length) {
      _recreateController();
    }
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final images = widget.images;
    final previewPage = widget.previewPage;
    final pc = _pageController;

    return Container(
      height: widget.cardHeight,
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
        child: images.isNotEmpty && pc != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () => widget.onImageTapZoom(
                      previewPage.clamp(0, images.length - 1),
                    ),
                    child: PageView.builder(
                      controller: pc,
                      itemCount: images.length,
                      onPageChanged: widget.onPreviewPageChanged,
                      itemBuilder: (context, index) {
                        return Image.file(
                          images[index],
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        );
                      },
                    ),
                  ),
                  if (images.length > 1)
                    Positioned(
                      bottom: 10,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(images.length, (i) {
                          final active = i == previewPage;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 16 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active ? cs.primary : Colors.black26,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black54,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => widget.onRemoveImageAt(
                          previewPage.clamp(0, images.length - 1),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.close_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : widget.video != null
                ? Stack(
                    alignment: Alignment.center,
                    fit: StackFit.expand,
                    children: [
                      _VideoPreview(file: widget.video!),
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
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.videocam_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              widget.maxVideoBadge,
                              style: const TextStyle(
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
                    loading: widget.loading,
                    colorScheme: cs,
                    theme: theme,
                    primaryText: widget.emptyPrimaryText,
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
    required this.primaryText,
  });

  final bool loading;
  final ColorScheme colorScheme;
  final ThemeData theme;
  final String primaryText;

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
              primaryText,
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
    final size = _controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return const Center(child: CircularProgressIndicator());
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
