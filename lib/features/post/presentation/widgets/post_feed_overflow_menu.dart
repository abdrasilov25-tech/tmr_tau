import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/storage/hidden_posts_storage.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';
import '../../../post_reports/data/repositories/post_reports_repository_impl.dart';

/// Три точки: как в новостях — сохранить, скрыть, пожаловаться, ссылка, своё: редактировать / удалить.
Future<void> showPostFeedOverflowMenu(
  BuildContext context, {
  required PostEntity post,
  required PostRepository postRepository,
  required GoRouter goRouter,
  String? currentUserId,
  VoidCallback? onSave,
  VoidCallback? onHide,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => _PostFeedOverflowSheet(
      post: post,
      currentUserId: currentUserId,
      postRepository: postRepository,
      goRouter: goRouter,
      onSave: onSave,
      onHide: onHide,
      parentContext: context,
    ),
  );
}

class _PostFeedOverflowSheet extends StatefulWidget {
  const _PostFeedOverflowSheet({
    required this.post,
    required this.currentUserId,
    required this.postRepository,
    required this.goRouter,
    required this.parentContext,
    this.onSave,
    this.onHide,
  });

  final PostEntity post;
  final String? currentUserId;
  final PostRepository postRepository;
  final GoRouter goRouter;
  final BuildContext parentContext;
  final VoidCallback? onSave;
  final VoidCallback? onHide;

  @override
  State<_PostFeedOverflowSheet> createState() => _PostFeedOverflowSheetState();
}

class _PostFeedOverflowSheetState extends State<_PostFeedOverflowSheet> {
  bool _showReportReasons = false;

  bool get _isOwn =>
      widget.currentUserId != null &&
      widget.currentUserId == widget.post.userId;

  static const _postBaseUrl = 'https://tmrtau.kz/post/';

  Future<void> _submitReport(String reason) async {
    final uid = widget.currentUserId;
    if (uid == null) {
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(
            content: Text('Войдите, чтобы отправить жалобу'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      final repo = PostReportsRepositoryImpl(Supabase.instance.client);
      await repo.createReport(
        postId: widget.post.id,
        reporterId: uid,
        reason: reason,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(
            content: Text('Жалоба отправлена. Спасибо!'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(
            content: Text('Не удалось отправить жалобу. Попробуйте позже.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final uid = widget.currentUserId;
    if (uid == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: const Text('Удалить публикацию?'),
        content: const Text('Это действие нельзя отменить.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.postRepository.deletePost(widget.post.id, uid);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onHide?.call();
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(
            content: Text('Публикация удалена'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (widget.parentContext.mounted) {
        ScaffoldMessenger.of(widget.parentContext).showSnackBar(
          const SnackBar(
            content: Text('Не удалось удалить'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _showReportReasons
            ? _buildReportSheet(context)
            : _buildMainSheet(context),
      ),
    );
  }

  Widget _buildMainSheet(BuildContext context) {
    return Column(
      key: const ValueKey('main'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        if (_isOwn) ...[
          _SheetTile(
            icon: Icons.edit_outlined,
            label: 'Редактировать',
            onTap: () {
              Navigator.of(context).pop();
              widget.goRouter.push(
                '/post/${widget.post.id}/edit',
                extra: widget.post,
              );
                                    },
          ),
          _SheetTile(
            icon: Icons.delete_outline,
            label: 'Удалить',
            color: Colors.red,
            onTap: _confirmDelete,
          ),
        ] else ...[
          _SheetTile(
            icon: widget.post.isSavedByMe
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            label: widget.post.isSavedByMe
                ? 'Убрать из сохранённых'
                : 'Сохранить',
            onTap: () {
              Navigator.of(context).pop();
              widget.onSave?.call();
            },
          ),
          _SheetTile(
            icon: Icons.hide_source_outlined,
            label: 'Скрыть',
            onTap: () async {
              Navigator.of(context).pop();
              await HiddenPostsStorage.hidePost(widget.post.id);
              widget.onHide?.call();
            },
          ),
          _SheetTile(
            icon: Icons.thumb_down_outlined,
            label: 'Не интересует',
            onTap: () async {
              Navigator.of(context).pop();
              await HiddenPostsStorage.hidePost(widget.post.id);
              widget.onHide?.call();
            },
          ),
          _SheetTile(
            icon: Icons.block_rounded,
            label: 'Заблокировать автора',
            color: Colors.red.shade700,
            onTap: () {
              Navigator.of(context).pop();
              _confirmBlock(widget.parentContext);
            },
          ),
          _SheetTile(
            icon: Icons.flag_outlined,
            label: 'Пожаловаться',
            color: Colors.red.shade700,
            onTap: () => setState(() => _showReportReasons = true),
          ),
        ],
        _SheetTile(
          icon: Icons.link_outlined,
          label: 'Скопировать ссылку',
          onTap: () {
            Clipboard.setData(
              ClipboardData(text: '$_postBaseUrl${widget.post.id}'),
            );
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ссылка скопирована'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _confirmBlock(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Text(
          'Заблокировать ${widget.post.userName ?? 'пользователя'}?',
        ),
        content: const Text(
          'Вы больше не будете видеть его публикации в этой ленте.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlgCtx),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () {
              Navigator.pop(dlgCtx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${widget.post.userName ?? 'Пользователь'} заблокирован',
                  ),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Заблокировать'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportSheet(BuildContext context) {
    const reasons = [
      'Спам',
      'Оскорбления или травля',
      'Обнажённость или сексуальный контент',
      'Нарушение авторских прав',
      'Насилие или опасный контент',
      'Ложная информация',
      'Другое',
    ];

    return Column(
      key: const ValueKey('report'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 4),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _showReportReasons = false),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Причина жалобы',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...reasons.map(
          (reason) => ListTile(
            title: Text(
              reason,
              style: TextStyle(color: Colors.red.shade700, fontSize: 14),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Colors.red.shade700,
            ),
            onTap: () => unawaited(_submitReport(reason)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(label, style: TextStyle(color: c, fontSize: 14)),
      onTap: onTap,
    );
  }
}
