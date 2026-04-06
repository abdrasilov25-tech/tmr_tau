import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../../post/domain/entities/post_comment_entity.dart';
import '../../../post/domain/entities/post_entity.dart';
import '../../../post/domain/repositories/post_repository.dart';
import '../../../../core/widgets/cached_avatar.dart';

/// Нижняя панель комментариев в стиле TikTok для Reels.
class ReelsCommentsSheet extends StatefulWidget {
  const ReelsCommentsSheet({
    super.key,
    required this.post,
    required this.onCommentsCountChanged,
  });

  final PostEntity post;
  final ValueChanged<int> onCommentsCountChanged;

  static Future<void> show(
    BuildContext context, {
    required PostEntity post,
    required ValueChanged<int> onCommentsCountChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReelsCommentsSheet(
        post: post,
        onCommentsCountChanged: onCommentsCountChanged,
      ),
    );
  }

  @override
  State<ReelsCommentsSheet> createState() => _ReelsCommentsSheetState();
}

class _ReelsCommentsSheetState extends State<ReelsCommentsSheet> {
  List<PostCommentEntity> _comments = [];
  bool _loading = true;
  bool _sending = false;
  late int _displayCommentsCount;
  final _textCtrl = TextEditingController();
  final _focusNode = FocusNode();

  PostEntity get _post => widget.post;

  @override
  void initState() {
    super.initState();
    _displayCommentsCount = widget.post.commentsCount;
    unawaited(_load());
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list =
          await context.read<PostRepository>().getComments(_post.id);
      if (mounted) setState(() => _comments = list);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Войдите, чтобы комментировать')),
        );
      }
      return;
    }
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await context.read<PostRepository>().addComment(
            postId: _post.id,
            userId: auth.user.id,
            text: text,
          );
      _textCtrl.clear();
      _focusNode.unfocus();
      _displayCommentsCount += 1;
      widget.onCommentsCountChanged(_displayCommentsCount);
      if (mounted) setState(() {});
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _timeAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'сейчас';
    if (d.inMinutes < 60) return '${d.inMinutes} мин';
    if (d.inHours < 24) return '${d.inHours} ч';
    if (d.inDays < 7) return '${d.inDays} д';
    return '${t.day}.${t.month}.${t.year}';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final auth = context.read<AuthBloc>().state;
    final loggedIn = auth is AuthAuthenticated;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.56,
        minChildSize: 0.38,
        maxChildSize: 0.92,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Color(0xFF141414),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 24,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  child: Row(
                    children: [
                      Text(
                        '$_displayCommentsCount комментариев',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white38,
                          ),
                        )
                      : _comments.isEmpty
                          ? Center(
                              child: Text(
                                'Пока нет комментариев\nБудьте первым',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  height: 1.4,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              itemCount: _comments.length,
                              itemBuilder: (context, i) {
                                final c = _comments[i];
                                final isReply = c.parentId != null;
                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: 14,
                                    left: isReply ? 20 : 0,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CachedAvatar(
                                        imageUrl: c.userAvatarUrl,
                                        radius: isReply ? 16 : 19,
                                        fallbackText:
                                            c.userName ?? c.userId,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    c.userName ??
                                                        'Пользователь',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 14,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _timeAgo(c.createdAt),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white
                                                        .withValues(
                                                            alpha: 0.45),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (c.replyToUserName !=
                                                null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Ответ ${c.replyToUserName}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.cyanAccent
                                                      .withValues(alpha: 0.85),
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 4),
                                            Text(
                                              c.text,
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withValues(alpha: 0.92),
                                                fontSize: 14,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    MediaQuery.of(context).padding.bottom + 8,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1C1C1C),
                    border: Border(
                      top: BorderSide(color: Colors.white10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textCtrl,
                          focusNode: _focusNode,
                          enabled: loggedIn && !_sending,
                          minLines: 1,
                          maxLines: 4,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: loggedIn
                                ? 'Добавить комментарий…'
                                : 'Войдите, чтобы комментировать',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.35),
                            ),
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.08),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                          ),
                          onSubmitted: (_) => unawaited(_send()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: const Color(0xFFFE2C55),
                        borderRadius: BorderRadius.circular(22),
                        child: InkWell(
                          onTap: loggedIn && !_sending ? () => unawaited(_send()) : null,
                          borderRadius: BorderRadius.circular(22),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: _sending
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    Icons.send_rounded,
                                    color: loggedIn
                                        ? Colors.white
                                        : Colors.white38,
                                    size: 22,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
