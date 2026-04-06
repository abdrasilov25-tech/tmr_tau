import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/themed_content_surface.dart';

/// Горизонтальные быстрые эмодзи в стиле TikTok: крупные круги, лёгкое «дыхание» и подпрыгивание по тапу.
class ChatQuickEmojiStrip extends StatefulWidget {
  const ChatQuickEmojiStrip({
    super.key,
    required this.onEmojiTap,
    this.streakDays,
    this.compact = false,
  });

  final ValueChanged<String> onEmojiTap;
  final int? streakDays;

  /// Для узких экранов (комментарии): чуть меньше тайлы.
  final bool compact;

  static const List<String> quickEmojis = [
    '👍', '❤️', '😂', '🔥', '👏', '😮', '🙏', '💯', '✨', '😍',
    '⭐', '🎉', '💪',
  ];

  @override
  State<ChatQuickEmojiStrip> createState() => _ChatQuickEmojiStripState();
}

class _ChatQuickEmojiStripState extends State<ChatQuickEmojiStrip>
    with SingleTickerProviderStateMixin {
  late AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  double _idleScale(int index, int total) {
    final t = _breath.value * 2 * math.pi;
    final phase = index * 0.42;
    return 1.0 + 0.055 * math.sin(t + phase);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tile = widget.compact ? 52.0 : 64.0;
    final font = widget.compact ? 30.0 : 38.0;
    final stripHeight = widget.compact ? 62.0 : 76.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.streakDays != null && widget.streakDays! > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer.withValues(alpha: 0.65),
                    scheme.tertiaryContainer.withValues(alpha: 0.45),
                  ],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.streakDays} дн.',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: SizedBox(
              height: stripHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                itemCount: ChatQuickEmojiStrip.quickEmojis.length,
                separatorBuilder: (context, index) =>
                    SizedBox(width: widget.compact ? 8 : 10),
                itemBuilder: (context, i) {
                  final e = ChatQuickEmojiStrip.quickEmojis[i];
                  return AnimatedBuilder(
                    animation: _breath,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _idleScale(
                          i,
                          ChatQuickEmojiStrip.quickEmojis.length,
                        ),
                        child: child,
                      );
                    },
                    child: _TikTokQuickStickerBubble(
                      emoji: e,
                      size: tile,
                      fontSize: font,
                      onCommit: () => widget.onEmojiTap(e),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TikTokQuickStickerBubble extends StatefulWidget {
  const _TikTokQuickStickerBubble({
    required this.emoji,
    required this.size,
    required this.fontSize,
    required this.onCommit,
  });

  final String emoji;
  final double size;
  final double fontSize;
  final VoidCallback onCommit;

  @override
  State<_TikTokQuickStickerBubble> createState() =>
      _TikTokQuickStickerBubbleState();
}

class _TikTokQuickStickerBubbleState extends State<_TikTokQuickStickerBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _pop;

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    widget.onCommit();
    _pop.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (mounted) await _pop.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scale = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
    );
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Text(
            widget.emoji,
            style: TextStyle(fontSize: widget.fontSize, height: 1.1),
          ),
        ),
      ),
    );
  }
}

class MessageComposerIconButton extends StatelessWidget {
  const MessageComposerIconButton({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 24,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class MessageComposerSendButton extends StatelessWidget {
  const MessageComposerSendButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

/// Голосовое: удержание (как в личных чатах).
class MessageComposerVoiceMicButton extends StatelessWidget {
  const MessageComposerVoiceMicButton({
    super.key,
    required this.isRecording,
    required this.seconds,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onHoldCancel,
  });

  final bool isRecording;
  final int seconds;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onHoldCancel;

  String get _timerLabel {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onHoldStart(),
      onPointerUp: (_) => onHoldEnd(),
      onPointerCancel: (_) => onHoldCancel(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: isRecording ? 90 : 48,
        height: 48,
        decoration: BoxDecoration(
          color: isRecording ? Colors.red : primary,
          borderRadius: BorderRadius.circular(24),
        ),
        child: isRecording
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mic, color: Colors.white, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    _timerLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            : const Icon(Icons.mic_none_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}

/// Видеокружок: удержание ~220 ms → родитель открывает запись.
class MessageComposerVideoHoldButton extends StatelessWidget {
  const MessageComposerVideoHoldButton({
    super.key,
    required this.onHoldArm,
    required this.onHoldDisarm,
  });

  final VoidCallback onHoldArm;
  final VoidCallback onHoldDisarm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Удерживайте для видеокружка',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onHoldArm(),
        onPointerUp: (_) => onHoldDisarm(),
        onPointerCancel: (_) => onHoldDisarm(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.videocam_rounded,
            size: 24,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

/// Единая нижняя панель ввода: как в личном чате (+, эмодзи, поле, видео/голос или отправка).
class UnifiedMessageComposerBar extends StatelessWidget {
  const UnifiedMessageComposerBar({
    super.key,
    required this.controller,
    this.focusNode,
    required this.hintText,
    required this.textHasContent,
    required this.onSend,
    this.onChanged,
    this.readOnly = false,
    this.showAttachmentButton = true,
    this.onAttachment,
    this.showEmojiButton = true,
    this.emojiPanelOpen = false,
    this.onEmojiToggle,
    /// В чатах при пустом поле показываем видеокружок + микрофон; в комментариях — нет.
    this.showVoiceVideoWhenEmpty = true,
    this.onVideoHoldArm,
    this.onVideoHoldDisarm,
    this.isRecordingVoice = false,
    this.voiceRecordSeconds = 0,
    this.onVoiceHoldStart,
    this.onVoiceHoldEnd,
    this.onVoiceHoldCancel,
    this.sending = false,
    this.elevation = 6,
    this.onFieldTap,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueListenable<bool> textHasContent;
  final VoidCallback onSend;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final bool showAttachmentButton;
  final VoidCallback? onAttachment;
  final bool showEmojiButton;
  final bool emojiPanelOpen;
  final VoidCallback? onEmojiToggle;
  final bool showVoiceVideoWhenEmpty;
  final VoidCallback? onVideoHoldArm;
  final VoidCallback? onVideoHoldDisarm;
  final bool isRecordingVoice;
  final int voiceRecordSeconds;
  final VoidCallback? onVoiceHoldStart;
  final VoidCallback? onVoiceHoldEnd;
  final VoidCallback? onVoiceHoldCancel;
  final bool sending;
  final double elevation;
  final VoidCallback? onFieldTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ThemedContentSurface.scaffoldElevated,
      elevation: elevation,
      shadowColor: Colors.black26,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (showAttachmentButton && onAttachment != null)
              MessageComposerIconButton(
                icon: Icons.add_circle_outline_rounded,
                onTap: onAttachment!,
              ),
            if (showEmojiButton && onEmojiToggle != null)
              MessageComposerIconButton(
                icon: emojiPanelOpen
                    ? Icons.keyboard_rounded
                    : Icons.emoji_emotions_outlined,
                onTap: onEmojiToggle!,
              ),
            const SizedBox(width: 2),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: readOnly,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: showVoiceVideoWhenEmpty
                      ? TextInputAction.newline
                      : TextInputAction.send,
                  onChanged: onChanged,
                  onSubmitted: (_) => onSend(),
                  onTap: onFieldTap,
                  decoration: InputDecoration(
                    hintText: hintText,
                    hintStyle: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 15,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            ValueListenableBuilder<bool>(
              valueListenable: textHasContent,
              builder: (context, hasContent, _) {
                if (hasContent) {
                  return sending
                      ? const Padding(
                          padding: EdgeInsets.all(10),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : MessageComposerSendButton(onTap: onSend);
                }
                if (!showVoiceVideoWhenEmpty) {
                  return const SizedBox(width: 8);
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onVideoHoldArm != null && onVideoHoldDisarm != null)
                      MessageComposerVideoHoldButton(
                        onHoldArm: onVideoHoldArm!,
                        onHoldDisarm: onVideoHoldDisarm!,
                      ),
                    if (onVoiceHoldStart != null &&
                        onVoiceHoldEnd != null &&
                        onVoiceHoldCancel != null)
                      MessageComposerVoiceMicButton(
                        isRecording: isRecordingVoice,
                        seconds: voiceRecordSeconds,
                        onHoldStart: onVoiceHoldStart!,
                        onHoldEnd: onVoiceHoldEnd!,
                        onHoldCancel: onVoiceHoldCancel!,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Нижняя шторка: набор эмодзи в текст комментария.
Future<void> showCommentEmojiPickerSheet(
  BuildContext context, {
  required ValueChanged<String> onEmoji,
}) {
  const grid = [
    '😀', '😃', '😄', '😁', '😅', '😂', '🤣', '😊', '😇', '🙂',
    '😉', '😍', '🥰', '😘', '😜', '🤪', '🤗', '🙃', '😢', '😭',
    '😡', '🤔', '🤝', '👍', '👎', '👏', '🙏', '🔥', '💯', '❤️',
    '⭐', '✨', '🎉', '💪', '🤝',
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: grid
              .map(
                (e) => Material(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      onEmoji(e);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Text(e, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    ),
  );
}
