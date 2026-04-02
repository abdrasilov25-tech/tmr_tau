import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

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
///
/// После захвата делает `context.go('/add-story', extra: StoryCameraResult(...))`.
class StoryCameraPage extends StatefulWidget {
  const StoryCameraPage({super.key});

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

  /// После возврата из «Настроек» с включённой камерой.
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

  /// Открыть галерею (фото).
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

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Превью камеры ─────────────────────────────────────
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

          // ── Верхние кнопки ────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Закрыть
                  _IconBtn(
                    icon: Icons.close,
                    onTap: () => context.pop(),
                  ),
                  if (!_initializing && _permissionGranted)
                    _IconBtn(
                      icon: _flashMode == FlashMode.torch
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      onTap: _toggleFlash,
                    ),
                ],
              ),
            ),
          ),

          // ── Таймер записи ─────────────────────────────────────
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

          // ── Подсказка ─────────────────────────────────────────
          if (!_isRecording && !_initializing && _permissionGranted)
            Positioned(
              bottom: bottomPad + 130,
              left: 0,
              right: 0,
              child: const Center(
                child: Text(
                  'Нажми — фото  •  Удерживай — видео',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),

          // ── Нижняя панель ─────────────────────────────────────
          if (!_initializing && _permissionGranted)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPad + 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Галерея
                  GestureDetector(
                    onTap: _pickFromGallery,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white38, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.photo_library_outlined,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),

                  // Кнопка захвата
                  _CaptureButton(
                    progress: _progressCtrl,
                    isRecording: _isRecording,
                    onTap: _takePicture,
                    onHoldStart: _startRecording,
                    onHoldEnd: _stopRecording,
                  ),

                  // Переключить камеру
                  if (_cameras.length > 1)
                    _IconBtn(
                      icon: Icons.flip_camera_ios_outlined,
                      size: 28,
                      onTap: _switchCamera,
                    )
                  else
                    const SizedBox(width: 48),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Вспомогательные виджеты ───────────────────────────────────────

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

class _CaptureButton extends StatelessWidget {
  const _CaptureButton({
    required this.progress,
    required this.isRecording,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final AnimationController progress;
  final bool isRecording;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) => onHoldStart(),
      onLongPressEnd: (_) => onHoldEnd(),
      onLongPressCancel: onHoldEnd,
      child: AnimatedBuilder(
        animation: progress,
        builder: (_, unused) => SizedBox(
          width: 84,
          height: 84,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: isRecording ? progress.value : 0,
                  strokeWidth: 4.5,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.red),
                  backgroundColor: Colors.white30,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: isRecording ? 34 : 66,
                height: isRecording ? 34 : 66,
                decoration: BoxDecoration(
                  color: isRecording ? Colors.red : Colors.white,
                  borderRadius:
                      BorderRadius.circular(isRecording ? 10 : 33),
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
