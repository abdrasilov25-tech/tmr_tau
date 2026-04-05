import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../story_camera_intent.dart';

/// Круглая кнопка захвата внизу пустого экрана сторис (как затвор камеры).
/// Короткое нажатие — открыть камеру для фото; длинное — сразу запись видео.
class StoryEmptyCaptureButton extends StatefulWidget {
  const StoryEmptyCaptureButton({
    super.key,
    required this.enabled,
    this.videoMode = false,
  });

  final bool enabled;
  final bool videoMode;

  @override
  State<StoryEmptyCaptureButton> createState() =>
      _StoryEmptyCaptureButtonState();
}

class _StoryEmptyCaptureButtonState extends State<StoryEmptyCaptureButton> {
  bool _down = false;
  static const _holdThreshold = Duration(milliseconds: 220);
  DateTime? _downAt;

  void _openCamera({required bool startRecording}) {
    if (!widget.enabled) return;
    if (startRecording) {
      context.push(
        '/story-camera?mode=video',
        extra: const StoryCameraStartIntent(recordVideoOnOpen: true),
      );
      return;
    }
    if (widget.videoMode) {
      context.push('/story-camera?mode=video');
    } else {
      context.push('/story-camera');
    }
  }

  void _onPointerDown() {
    _down = true;
    _downAt = DateTime.now();
    Future<void>.delayed(_holdThreshold, () {
      if (_down && mounted) {
        _down = false;
        _openCamera(startRecording: true);
      }
    });
  }

  void _onPointerUp() {
    final wasDown = _down;
    _down = false;
    if (!wasDown) return;
    final elapsed = DateTime.now().difference(_downAt ?? DateTime.now());
    if (elapsed < _holdThreshold) {
      _openCamera(startRecording: widget.videoMode);
    }
  }

  void _onPointerCancel() {
    _down = false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Listener(
          onPointerDown: (_) => widget.enabled ? _onPointerDown() : null,
          onPointerUp: (_) => _onPointerUp(),
          onPointerCancel: (_) => _onPointerCancel(),
          child: SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.95),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.92),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.black.withValues(alpha: 0.78),
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.videoMode
              ? 'Нажми — камера  •  Удерживай — сразу запись'
              : 'Нажми — фото  •  Удерживай — видео',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 12,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}
