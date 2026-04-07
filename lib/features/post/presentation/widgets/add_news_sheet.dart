import 'dart:io';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/supabase_constants.dart';
import '../../../../core/services/geo_service.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';
import '../pages/add_post_page.dart';
import '../pages/video_trim_page.dart';
import 'post_photo_gallery.dart';

enum _MediaType { photo, video }

enum _NewsPhotoSource { galleryMulti, camera }

/// Открывает bottom-sheet для создания новости.
/// Возвращает [PostEntity] при успешной публикации или `null` при закрытии.
Future<PostEntity?> showAddNewsSheet(
  BuildContext context, {
  required String userId,
  String? cityFilter,
}) {
  return showModalBottomSheet<PostEntity?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddNewsSheetContent(
      userId: userId,
      cityFilter: cityFilter,
    ),
  );
}

class _AddNewsSheetContent extends StatefulWidget {
  const _AddNewsSheetContent({
    required this.userId,
    this.cityFilter,
  });

  final String userId;
  final String? cityFilter;

  @override
  State<_AddNewsSheetContent> createState() => _AddNewsSheetContentState();
}

class _AddNewsSheetContentState extends State<_AddNewsSheetContent> {
  final List<File> _images = [];
  File? _video;
  final _captionController = TextEditingController();
  bool _loading = false;
  int _previewPage = 0;

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
  static const int _maxVideoSeconds = 300;

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

  bool get _hasMedia => _images.isNotEmpty || _video != null;
  bool get _canPublish => _hasMedia || _captionController.text.trim().isNotEmpty;

  // ─── Media picking ────────────────────────────────────────────────────────

  Future<void> _showPickMediaSheet() async {
    final choice = await showModalBottomSheet<_MediaType>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Добавить фото или видео',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: Colors.black87),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, size: 28),
                title: const Text('Фото'),
                subtitle: Text('До $_maxNewsPhotos фото: галерея (несколько) или камера'),
                onTap: () => Navigator.pop(ctx, _MediaType.photo),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined, size: 28),
                title: const Text('Видео'),
                subtitle: const Text('До 5 минут'),
                onTap: () => Navigator.pop(ctx, _MediaType.video),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _MediaType.photo) {
      await _pickNewsPhotos();
    } else {
      await _pickVideo();
    }
  }

  Future<void> _pickNewsPhotos() async {
    final action = await showModalBottomSheet<_NewsPhotoSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Фото к новости',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: Colors.black87),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, size: 28),
                title: const Text('Несколько из галереи'),
                subtitle: Text('До $_maxNewsPhotos шт. · можно добавлять частями'),
                onTap: () => Navigator.pop(ctx, _NewsPhotoSource.galleryMulti),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined, size: 28),
                title: const Text('Камера'),
                subtitle: const Text('Одно фото, можно повторить'),
                onTap: () => Navigator.pop(ctx, _NewsPhotoSource.camera),
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Уже максимум $_maxNewsPhotos фото'), behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }
      final addCount = picked.length > room ? room : picked.length;
      if (picked.length > room && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Добавлено $addCount из ${picked.length} (лимит $_maxNewsPhotos)'), behavior: SnackBarBehavior.floating),
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
            SnackBar(content: Text('Уже $_maxNewsPhotos фото — удалите лишние'), behavior: SnackBarBehavior.floating),
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
      builder: (ctx) => SafeArea(
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
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: const Text('Камера'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
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
          const SnackBar(content: Text('Не удалось определить длительность видео'), behavior: SnackBarBehavior.floating),
        );
      }
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!mounted) return;
    setState(() => _loading = false);

    if (durationSeconds > _maxVideoSeconds) {
      final maxForTrim = min(_maxVideoSeconds, durationSeconds);
      final trimmed = await Navigator.of(context).push<File?>(
        MaterialPageRoute<File?>(
          fullscreenDialog: true,
          builder: (_) => VideoTrimPage(
            sourceFile: file,
            maxDurationSeconds: maxForTrim,
            contextLabel: 'новости',
          ),
        ),
      );
      if (!mounted || trimmed == null) return;
      setState(() {
        _video = trimmed;
        _images.clear();
        _previewPage = 0;
      });
    } else {
      setState(() {
        _video = file;
        _images.clear();
        _previewPage = 0;
      });
    }
  }

  Future<void> _trimCurrentVideo() async {
    final file = _video;
    if (file == null || !mounted) return;
    setState(() => _loading = true);
    int? durationSec;
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      durationSec = (controller.value.duration.inMilliseconds / 1000).ceil().clamp(1, 1 << 20);
      await controller.dispose();
    } catch (_) {
      durationSec = null;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (durationSec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть видео для обрезки'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    final maxDurationSeconds = min(_maxVideoSeconds, durationSec);
    final trimmed = await Navigator.of(context).push<File?>(
      MaterialPageRoute<File?>(
        fullscreenDialog: true,
        builder: (_) => VideoTrimPage(
          sourceFile: file,
          maxDurationSeconds: maxDurationSeconds,
          contextLabel: 'новости',
        ),
      ),
    );
    if (!mounted || trimmed == null) return;
    setState(() => _video = trimmed);
  }

  // ─── Upload helpers ────────────────────────────────────────────────────────

  Future<String> _uploadImage(File file) async {
    const uuid = Uuid();
    final ext = file.path.split('.').last;
    final path = '${uuid.v4()}.$ext';
    await Supabase.instance.client.storage
        .from(SupabaseConstants.bucketPosts)
        .upload(path, file, fileOptions: const FileOptions(upsert: true));
    return Supabase.instance.client.storage.from(SupabaseConstants.bucketPosts).getPublicUrl(path);
  }

  Future<String> _uploadVideo(File file) async {
    const uuid = Uuid();
    final ext = file.path.split('.').last;
    final path = 'videos/${uuid.v4()}.$ext';
    await Supabase.instance.client.storage
        .from(SupabaseConstants.bucketPosts)
        .upload(path, file, fileOptions: const FileOptions(upsert: true));
    return Supabase.instance.client.storage.from(SupabaseConstants.bucketPosts).getPublicUrl(path);
  }

  // ─── Publish ───────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    final caption = _captionController.text.trim();
    if (_images.isEmpty && _video == null && caption.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Напишите текст или добавьте фото/видео'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    if (_newsHasPoll) {
      final pq = _newsPollQuestion.text.trim();
      final opts = _newsPollOptions.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
      if (pq.isEmpty || opts.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Опрос: укажите вопрос и минимум 2 варианта'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
    }

    final postRepository = context.read<PostRepository>();
    final geoService = context.read<GeoService>();
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
        if (_newsAttachLocation) {
          location = await geoService.getCurrentLocation();
        }
      } catch (_) {
        location = null;
      }

      // Читаем выбранный город из SharedPreferences (как в AddPostPage)
      final prefs = await SharedPreferences.getInstance();
      final city = widget.cityFilter ?? prefs.getString('news_selected_city');

      final pollOpts = _newsHasPoll
          ? _newsPollOptions.map((c) => c.text.trim()).where((s) => s.isNotEmpty).take(8).toList()
          : const <String>[];

      final createdPost = await postRepository.createPost(
        userId: widget.userId,
        imageUrl: imageUrl,
        imageUrls: imageUrls,
        caption: caption,
        videoUrl: videoUrl,
        videoDurationSeconds: videoDurationSeconds,
        kind: 'news',
        latitude: _newsAttachLocation ? location?.latitude : null,
        longitude: _newsAttachLocation ? location?.longitude : null,
        city: city,
        isAnonymous: _newsAnonymous,
        locationLabel: _newsAttachLocation
            ? (_newsLocationLabel.text.trim().isNotEmpty ? _newsLocationLabel.text.trim() : null)
            : null,
        pollQuestion: _newsHasPoll && pollOpts.length >= 2 ? _newsPollQuestion.text.trim() : null,
        pollOptions: pollOpts,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новость опубликована'), behavior: SnackBarBehavior.floating),
      );
      if (mounted) Navigator.of(context).pop(createdPost);
    } catch (e) {
      if (!mounted) return;
      String message = 'Ошибка при публикации';
      if (e is StorageException) {
        message = 'Storage: создайте бакет «posts» в Supabase и добавьте политики загрузки';
      } else if (e is PostgrestException) {
        message = 'База данных: проверьте таблицу posts и выполните schema.sql';
      } else {
        message = 'Ошибка: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 5), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF4F4F5),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Отступ для клавиатуры
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Новая новость',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0A0A0A),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _loading || !_canPublish ? null : _publish,
                  style: FilledButton.styleFrom(
                    elevation: 0,
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                        )
                      : const Text('Опубликовать', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          // Scrollable body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Текст
                  TextField(
                    controller: _captionController,
                    onChanged: (_) => setState(() {}),
                    maxLines: 6,
                    minLines: 3,
                    style: const TextStyle(
                      fontSize: 17,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF0A0A0A),
                    ),
                    decoration: InputDecoration(
                      hintText: 'О чём хотите рассказать?',
                      hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 17),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Медиа
                  GestureDetector(
                    onTap: _loading ? null : _showPickMediaSheet,
                    child: SizedBox(
                      height: 200,
                      child: PostMediaPickerCard(
                        cardHeight: 200,
                        loading: _loading,
                        images: List<File>.unmodifiable(_images),
                        video: _video,
                        previewPage: _previewPage,
                        onPreviewPageChanged: (i) => setState(() => _previewPage = i),
                        onRemoveImageAt: (i) {
                          setState(() {
                            _images.removeAt(i);
                            _previewPage = _images.isEmpty ? 0 : _previewPage.clamp(0, _images.length - 1);
                          });
                        },
                        onImageTapZoom: (i) => openLocalPhotoZoom(context, _images, i),
                        maxVideoBadge: 'Видео до 5 мин',
                        emptyPrimaryText: 'Фото или видео — по желанию',
                      ),
                    ),
                  ),
                  if (_video != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _loading ? null : _trimCurrentVideo,
                        icon: const Icon(Icons.content_cut_outlined, size: 18),
                        label: const Text('Обрезать видео'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Опции
                  NewsThreadsOptions(
                    anonymous: _newsAnonymous,
                    onAnonymousChanged: (v) => setState(() => _newsAnonymous = v),
                    attachLocation: _newsAttachLocation,
                    onAttachLocationChanged: (v) => setState(() => _newsAttachLocation = v),
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
                      setState(() => _newsPollOptions.removeAt(i).dispose());
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
