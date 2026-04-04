import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Результат записи «видеокружка» в личном чате.
class DmHoldVideoResult {
  const DmHoldVideoResult({required this.file});

  final File file;
}

/// Полноэкранная круглая запись: открывается при нажатии, запись стартует после
/// инициализации камеры; [Listener.onPointerUp] останавливает и закрывает с результатом.
class DmHoldVideoOverlay extends StatefulWidget {
  const DmHoldVideoOverlay({super.key});

  static const int maxSeconds = 60;

  @override
  State<DmHoldVideoOverlay> createState() => _DmHoldVideoOverlayState();
}

class _DmHoldVideoOverlayState extends State<DmHoldVideoOverlay> {
  CameraController? _ctrl;
  bool _ready = false;
  bool _recording = false;
  bool _stopping = false;
  int _seconds = 0;
  Timer? _tick;
  Timer? _maxTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final frontIdx = cameras
          .indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      final desc = frontIdx >= 0 ? cameras[frontIdx] : cameras.first;
      final ctrl = CameraController(
        desc,
        ResolutionPreset.medium,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      _ctrl = ctrl;
      setState(() => _ready = true);
      await _startRecording();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _startRecording() async {
    final ctrl = _ctrl;
    if (ctrl == null || !ctrl.value.isInitialized || _recording) return;
    try {
      await ctrl.startVideoRecording();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
    _maxTimer = Timer(
      const Duration(seconds: DmHoldVideoOverlay.maxSeconds),
      () {
        if (_recording) unawaited(_finishRecording());
      },
    );
  }

  Future<void> _finishRecording() async {
    if (_stopping) return;
    if (!_recording) {
      if (!_ready && mounted) Navigator.of(context).pop();
      return;
    }
    _stopping = true;
    _tick?.cancel();
    _maxTimer?.cancel();
    final ctrl = _ctrl;
    if (ctrl == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    try {
      if (!ctrl.value.isRecordingVideo) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final x = await ctrl.stopVideoRecording();
      final file = File(x.path);
      if (!mounted) return;
      if (_seconds < 1) {
        try {
          await file.delete();
        } catch (_) {}
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }
      if (!mounted) return;
      Navigator.of(context).pop(DmHoldVideoResult(file: file));
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _cancelFromBack() async {
    _tick?.cancel();
    _maxTimer?.cancel();
    final ctrl = _ctrl;
    if (ctrl != null && ctrl.value.isRecordingVideo) {
      try {
        final x = await ctrl.stopVideoRecording();
        try {
          await File(x.path).delete();
        } catch (_) {}
      } catch (_) {}
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _maxTimer?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  static String _formatTime(int sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final d = MediaQuery.sizeOf(context).shortestSide * 0.72;

    return PopScope(
      canPop: !_recording,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _cancelFromBack();
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerUp: (_) => unawaited(_finishRecording()),
        child: Scaffold(
          backgroundColor: const Color(0xFF0B0B0E).withValues(alpha: 0.97),
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready && _ctrl != null && _ctrl!.value.isInitialized)
                Center(
                  child: ClipOval(
                    child: SizedBox(
                      width: d,
                      height: d,
                      child: FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: d,
                          height: d /
                              (_ctrl!.value.aspectRatio > 0.01
                                  ? _ctrl!.value.aspectRatio
                                  : 1.0),
                          child: CameraPreview(_ctrl!),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      ),
                      SizedBox(height: pad.top > 0 ? 20 : 24),
                      Text(
                        'Подключаем камеру…',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_recording)
                Positioned(
                  top: pad.top + 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withValues(alpha: 0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _formatTime(_seconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 24,
                right: 24,
                bottom: pad.bottom + 32,
                child: Text(
                  _recording
                      ? 'Отпустите палец или коснитесь экрана, чтобы отправить'
                      : 'Идёт запись после появления кружка…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 15,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
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
