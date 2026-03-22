import 'package:flutter/material.dart';

import '../../../../core/widgets/app_loading.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';
import '../pages/post_detail_page.dart';

/// Загружает новость по id **один раз** (не в [build] роутера).
class PostDetailRoutePage extends StatefulWidget {
  const PostDetailRoutePage({
    super.key,
    required this.postId,
    required this.postRepository,
  });

  final String postId;
  final PostRepository postRepository;

  @override
  State<PostDetailRoutePage> createState() => _PostDetailRoutePageState();
}

class _PostDetailRoutePageState extends State<PostDetailRoutePage> {
  late Future<PostEntity?> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = widget.postRepository.getPostById(widget.postId);
  }

  void _retry() {
    setState(() {
      _loadFuture = widget.postRepository.getPostById(widget.postId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PostEntity?>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: AppLoading()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Не удалось загрузить: ${snapshot.error}'),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retry,
                      child: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final fetched = snapshot.data;
        if (fetched == null) {
          return const Scaffold(
            body: Center(child: Text('Новость не найдена')),
          );
        }
        return PostDetailPage(
          post: fetched,
          postRepository: widget.postRepository,
        );
      },
    );
  }
}
