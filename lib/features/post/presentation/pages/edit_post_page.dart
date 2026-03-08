import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';

class EditPostPage extends StatefulWidget {
  const EditPostPage({super.key, required this.post});

  final PostEntity post;

  @override
  State<EditPostPage> createState() => _EditPostPageState();
}

class _EditPostPageState extends State<EditPostPage> {
  late final TextEditingController _captionController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.post.caption);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final caption = _captionController.text.trim();
    setState(() => _loading = true);
    try {
      await context.read<PostRepository>().updatePost(
            postId: widget.post.id,
            caption: caption,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новость обновлена')),
      );
      context.pop(widget.post.copyWith(caption: caption));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Редактировать новость',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Сохранить',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.post.imageUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.post.imageUrl,
                width: double.infinity,
                height: 240,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 240,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined, size: 48),
                ),
              ),
            ),
          if (widget.post.videoUrl != null && widget.post.videoUrl!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(Icons.videocam, size: 48, color: Colors.grey.shade600),
              ),
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _captionController,
            decoration: InputDecoration(
              hintText: 'Подпись к новости',
              hintStyle: TextStyle(color: Colors.grey.shade500),
              border: InputBorder.none,
            ),
            maxLines: 4,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }
}
