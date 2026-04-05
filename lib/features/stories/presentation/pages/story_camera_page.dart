import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/router/go_router_pop_safe.dart';
import '../utils/story_media_permissions.dart';

/// Результат съёмки сторис-камеры.
class StoryCameraResult {
  const StoryCameraResult({required this.file, required this.isVideo});
  final File file;
  final bool isVideo;
}

/// Камера в стиле Instagram для создания сторис.
///
/// - Нажатие → фото
/// - Удержание → видео (до 60 секунд, прогресс-кольцо вокруг кнопки)
/// - «Свободные руки»: тап — старт/стоп записи
///
/// После захвата делает `context.go('/add-story', extra: StoryCameraResult(...))`.
class StoryCameraPage extends StatefulWidget {
  const StoryCameraPage({super.key, this.isVideoMode = false});

  /// Подсветка «ВИДЕО» в нижней полосе режимов (как Reels).
  final bool isVideoMode;

  @override
  State<StoryCameraPage> createState() => _StoryCameraPageState();
}

class _StoryCameraPageState extends State<StoryCameraPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraCtrl;
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;

  bool _initializing = true;
  bool _permissionGranted = false;
  bool _isRecording = false;
  bool _handsFree = false;

  late final AnimationController _progressCtrl;
  static const Duration _maxRecordDuration = Duration(seconds: 60);

  Timer? _recordTimer;
  int _recordedSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progressCtrl = AnimationController(
      vsync: this,
      duration: _maxRecordDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _stopRecording();
        }
      });
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _progressCtrl.dispose();
    _recordTimer?.cancel();
    _cameraCtrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final ctrl = _cameraCtrl;
      if (ctrl != null) {
        ctrl.dispose();
        _cameraCtrl = null;
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (!_permissionGranted) {
        unawaited(_retryCameraPermissionAfterResume());
        return;
      }
      final needReconnect = _cameraCtrl == null ||
          !(_cameraCtrl?.value.isInitialized ?? false);
      if (_cameras.isNotEmpty && needReconnect) {
        unawaited(_initCamera(_cameras[_cameraIndex]));
      }
    }
  }

  Future<void> _retryCameraPermissionAfterResume() async {
    var s = await Permission.camera.status;
    if (s.isGranted) {
      if (!mounted) return;
      setState(() {
        _permissionGranted = true;
        _initializing = true;
      });
      await _bootstrapCamerasAfterPermission();
      return;
    }
    s = await Permission.camera.request();
    if (!mounted) return;
    if (s.isGranted) {
      setState(() {
        _permissionGranted = true;
        _initializing = true;
      });
      await _bootstrapCamerasAfterPermission();
    }
  }

  Future<void> _init() async {
    var camStatus = await Permission.camera.status;
    if (!camStatus.isGranted) {
      camStatus = await Permission.camera.request();
    }
    final micStatus = await Permission.microphone.status;
    if (!mounted) return;

    if (!camStatus.isGranted) {
      setState(() {
        _permissionGranted = false;
        _initializing = false;
      });
      return;
    }
    setState(() => _permissionGranted = true);

    await _bootstrapCamerasAfterPermission();
    if (!mounted) return;
    if (micStatus.isDenied || micStatus.isRestricted) {
      await Permission.microphone.request();
    }
  }

  Future<void> _bootstrapCamerasAfterPermission() async {
    try {
      _cameras = await availableCameras();
    } catch (_) {
      if (mounted) setState(() => _initializing = false);
      return;
    }

    if (_cameras.isEmpty) {
      if (mounted) setState(() => _initializing = false);
      return;
    }

    final frontIdx =
        _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.front);
    _cameraIndex = frontIdx >= 0 ? frontIdx : 0;

    await _initCamera(_cameras[_cameraIndex]);
  }

  Future<void> _initCamera(CameraDescription desc) async {
    final prev = _cameraCtrl;
    _cameraCtrl = null;
    await prev?.dispose();

    final ctrl = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _cameraCtrl = ctrl;
    try {
      await ctrl.initialize();
      if (!ctrl.value.isInitialized || !mounted) return;
      await ctrl.setFlashMode(_flashMode);
      setState(() => _initializing = false);
    } catch (_) {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecording) return;
    setState(() => _initializing = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initCamera(_cameras[_cameraIndex]);
  }

  Future<void> _toggleFlash() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;
    final next =
        _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await ctrl.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (_) {}
  }

  Future<void> _takePicture() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;
    try {
      final xFile = await ctrl.takePicture();
      if (!mounted) return;
      context.go(
        '/add-story',
        extra: StoryCameraResult(file: File(xFile.path), isVideo: false),
      );
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !ctrl.value.isInitialized || _isRecording) return;
    try {
      await ctrl.startVideoRecording();
      _progressCtrl.forward(from: 0);
      _recordedSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordedSeconds++);
      });
      if (mounted) setState(() => _isRecording = true);
    } catch (_) {}
  }

  Future<void> _stopRecording() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !_isRecording) return;
    _progressCtrl.stop();
    _recordTimer?.cancel();
    try {
      final xFile = await ctrl.stopVideoRecording();
      if (!mounted) return;
      setState(() => _isRecording = false);
      context.go(
        '/add-story?video=1',
        extra: StoryCameraResult(file: File(xFile.path), isVideo: true),
      );
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
    }
  }

  /// Закрытие без перехода на экран редактирования (удаляем временный файл).
  Future<void> _cancelRecording() async {
    final ctrl = _cameraCtrl;
    if (ctrl == null || !_isRecording) return;
    _progressCtrl.reset();
    _recordTimer?.cancel();
    try {
      final xFile = await ctrl.stopVideoRecording();
      try {
        final f = File(xFile.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => _isRecording = false);
  }

  Future<void> _onClosePressed() async {
    if (_isRecording) {
      await _cancelRecording();
      return;
    }
    if (!mounted) return;
    context.popOrGoHomeFeed();
  }

  void _showCameraSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Настройки камеры',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Дополнительные параметры появятся позже.',
                style: TextStyle(color: Colors.grey.shade400, height: 1.35),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Закрыть'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleHandsFree() {
    setState(() => _handsFree = !_handsFree);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _handsFree
              ? 'Свободные руки: нажми на круг — начать или остановить запись'
              : 'Обычный режим: нажми — фото, удерживай — видео',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _stubSoon(String label) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — скоро')),
    );
  }

  Future<void> _pickFromGallery() async {
    if (_isRecording) return;
    final access =
        await StoryMediaPermissions.galleryAccess(forVideo: false);
    switch (access) {
      case StoryGalleryAccess.ok:
        break;
      case StoryGalleryAccess.deniedInDialog:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Разрешите доступ к фото в системном запросе или попробуйте снова.',
            ),
          ),
        );
        return;
      case StoryGalleryAccess.needsSettings:
        if (!mounted) return;
        await StoryMediaPermissions.offerOpenSettings(
          context,
          message:
              'Доступ к фото для Tmr Tau отключён. Включите его в настройках.',
        );
        return;
    }
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null || !mounted) return;
    context.go(
      '/add-story',
      extra: StoryCameraResult(file: File(xFile.path), isVideo: false),
    );
  }

  String get _hintText {
    if (_handsFree) {
      return 'Нажми на круг — начать или остановить запись';
    }
    return 'Нажми — фото  •  Удерживай — видео';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_initializing)
            const Center(child: CircularProgressIndicator(color: Colors.white))
          else if (!_permissionGranted)
            _PermissionView(
              onOpenSettings: () => StoryMediaPermissions.offerOpenSettings(
                context,
                message:
                    'Чтобы снимать сторис, включите доступ к камере для Tmr Tau '
                    'в настройках устройства.',
              ),
            )
          else if (_cameraCtrl != null && _cameraCtrl!.value.isInitialized)
            _CameraPreviewFill(controller: _cameraCtrl!)
          else
            const Center(
              child: Text(
                'Камера недоступна',
                style: TextStyle(color: Colors.white70),
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  _IconBtn(
                    icon: Icons.close,
                    onTap: _onClosePressed,
                  ),
                  const Spacer(),
                  if (!_initializing && _permissionGranted) ...[
                    _IconBtn(
                      icon: _flashMode == FlashMode.torch
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      onTap: _toggleFlash,
                    ),
                    const SizedBox(width: 8),
                    _IconBtn(
                      icon: Icons.settings_outlined,
                      onTap: _showCameraSettingsSheet,
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (!_initializing &&
              _permissionGranted &&
              _cameraCtrl != null &&
              _cameraCtrl!.value.isInitialized)
            Positioned(
              left: 4,
              top: 72,
              bottom: bottomPad + 200,
              child: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _CameraToolTile(
                        icon: Icons.text_fields_rounded,
                        label: 'Создать',
                        onTap: () => context.go('/add-story'),
                      ),
                      _CameraToolTile(
                        icon: Icons.loop_rounded,
                        label: 'Бумеранг',
                        onTap: () => _stubSoon('Бумеранг'),
                      ),
                      _CameraToolTile(
                        icon: Icons.grid_view_rounded,
                        label: 'Коллаж',
                        onTap: () => _stubSoon('Коллаж'),
                      ),
                      _CameraToolTile(
                        icon: Icons.front_hand_rounded,
                        label: 'Свободные\nруки',
                        active: _handsFree,
                        onTap: _toggleHandsFree,
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_isRecording)
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, color: Colors.white, size: 8),
                      const SizedBox(width: 6),
                      Text(
                        '${_recordedSeconds ~/ 60}:${(_recordedSeconds % 60).toString().padLeft(2, '0')}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (!_isRecording && !_initializing && _permissionGranted)
            Positioned(
              bottom: bottomPad + 168,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  _hintText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),

          if (!_initializing && _permissionGranted)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPad,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CaptureButton(
                        progress: _progressCtrl,
                        isRecording: _isRecording,
                        handsFree: _handsFree,
                        onTap: _takePicture,
                        onHoldStart: _startRecording,
                        onHoldEnd: _stopRecording,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _GalleryThumb(onTap: _pickFromGallery),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _ModePill(
                                  label: 'ПУБЛИКАЦИЯ',
                                  active: false,
                                  dimmed: true,
                                  onTap: () =>
                                      context.go('/add-publication'),
                                ),
                                _ModePill(
                                  label: 'ИСТОРИЯ',
                                  active: !widget.isVideoMode,
                                  onTap: () => context.go('/story-camera'),
                                ),
                                _ModePill(
                                  label: 'ВИДЕО',
                                  active: widget.isVideoMode,
                                  onTap: () =>
                                      context.go('/story-camera?mode=video'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_cameras.length > 1)
                          _IconBtn(
                            icon: Icons.flip_camera_ios_outlined,
                            size: 26,
                            onTap: _switchCamera,
                          )
                        else
                          const SizedBox(width: 46, height: 46),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraToolTile extends StatelessWidget {
  const _CameraToolTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: active
                    ? Colors.white.withValues(alpha: 0.22)
                    : Colors.black38,
                shape: BoxShape.circle,
                border: Border.all(
                  color: active
                      ? Colors.white54
                      : Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 72,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.active,
    required this.onTap,
    this.dimmed = false,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: active
                ? Colors.white
                : (dimmed ? Colors.white38 : Colors.white60),
            fontSize: 13,
            fontWeight: active ? FontWeight.w800 : FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white38, width: 1.5),
        ),
        child: const Icon(
          Icons.photo_library_outlined,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

class _CameraPreviewFill extends StatelessWidget {
  const _CameraPreviewFill({required this.controller});
  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final preview = controller.value.previewSize;
        return SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: preview?.height ?? constraints.maxWidth,
              height: preview?.width ?? constraints.maxHeight,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }
}

class _CaptureButton extends StatefulWidget {
  const _CaptureButton({
    required this.progress,
    required this.isRecording,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
    this.handsFree = false,
  });

  final AnimationController progress;
  final bool isRecording;
  final bool handsFree;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  State<_CaptureButton> createState() => _CaptureButtonState();
}

class _CaptureButtonState extends State<_CaptureButton> {
  bool _isDown = false;
  static const _holdThreshold = Duration(milliseconds: 200);
  DateTime? _downAt;

  void _handlePointerDown(PointerDownEvent _) {
    if (widget.handsFree) {
      _isDown = true;
      _downAt = DateTime.now();
      return;
    }
    _isDown = true;
    _downAt = DateTime.now();
    Future.delayed(_holdThreshold, () {
      if (_isDown && mounted) widget.onHoldStart();
    });
  }

  void _handlePointerUp(PointerUpEvent _) {
    if (widget.handsFree) {
      final wasDown = _isDown;
      _isDown = false;
      if (!wasDown) return;
      final elapsed = DateTime.now().difference(_downAt ?? DateTime.now());
      if (elapsed > const Duration(milliseconds: 500)) {
        return;
      }
      if (widget.isRecording) {
        widget.onHoldEnd();
      } else {
        widget.onHoldStart();
      }
      return;
    }
    final wasDown = _isDown;
    _isDown = false;
    if (!wasDown) return;
    final elapsed = DateTime.now().difference(_downAt ?? DateTime.now());
    if (elapsed < _holdThreshold) {
      widget.onTap();
    } else {
      widget.onHoldEnd();
    }
  }

  void _handlePointerCancel(PointerCancelEvent _) {
    if (widget.handsFree) {
      _isDown = false;
      return;
    }
    if (_isDown) {
      _isDown = false;
      widget.onHoldEnd();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: AnimatedBuilder(
        animation: widget.progress,
        builder: (context, _) => SizedBox(
          width: 84,
          height: 84,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: widget.isRecording ? widget.progress.value : 0,
                  strokeWidth: 4.5,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                  backgroundColor: Colors.white30,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: widget.isRecording ? 34 : 66,
                height: widget.isRecording ? 34 : 66,
                decoration: BoxDecoration(
                  color: widget.isRecording ? Colors.red : Colors.white,
                  borderRadius: BorderRadius.circular(
                    widget.isRecording ? 10 : 33,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.size = 26,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({required this.onOpenSettings});
  final Future<void> Function() onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Нет доступа к камере',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Нажмите «Разрешить» в системном запросе или откройте настройки ниже.',
              style: TextStyle(color: Colors.white54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => onOpenSettings(),
              child: const Text('Открыть настройки'),
            ),
          ],
        ),
      ),
    );
  }
}
