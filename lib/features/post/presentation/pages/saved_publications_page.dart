import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/bloc/auth_bloc.dart';
import '../../domain/entities/post_entity.dart';
import '../../domain/repositories/post_repository.dart';
import '../widgets/post_grid_engagement_overlay.dart';

class SavedPublicationsPage extends StatefulWidget {
  const SavedPublicationsPage({super.key});

  @override
  State<SavedPublicationsPage> createState() => _SavedPublicationsPageState();
}

class _SavedPublicationsPageState extends State<SavedPublicationsPage> {
  bool _loading = true;
  List<PostEntity> _posts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = context.read<AuthBloc>().state;
    if (auth is! AuthAuthenticated) {
      setState(() {
        _posts = const [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final list = await context
          .read<PostRepository>()
          .getSavedPublications(auth.user.id, limit: 200);
      if (!mounted) return;
      setState(() {
        _posts = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сохранённые')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _posts.isEmpty
              ? Center(
                  child: Text(
                    'Пока нет сохранённых публикаций',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Builder(
                    builder: (context) {
                      final dpr = MediaQuery.devicePixelRatioOf(context);
                      final gridThumbPx = (MediaQuery.sizeOf(context).width /
                              3 *
                              dpr)
                          .round()
                          .clamp(64, 2048);
                      return GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 4,
                          mainAxisSpacing: 4,
                        ),
                        itemCount: _posts.length,
                        itemBuilder: (context, index) {
                          final p = _posts[index];
                          final hasVideo =
                              PostGridEngagementOverlay.isProbablyVideoPost(p);
                          late final Widget media;
                          if (p.imageUrl.isNotEmpty) {
                            media = CachedNetworkImage(
                              imageUrl: p.imageUrl,
                              fit: BoxFit.cover,
                              memCacheWidth: gridThumbPx,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              placeholder: (_, __) =>
                                  ColoredBox(color: Colors.grey.shade200),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey.shade200,
                                child:
                                    const Icon(Icons.broken_image_outlined),
                              ),
                            );
                          } else {
                            media = ColoredBox(
                              color: Colors.grey.shade300,
                              child: Icon(
                                hasVideo
                                    ? Icons.videocam_rounded
                                    : Icons.article_outlined,
                                color: Colors.white70,
                                size: 30,
                              ),
                            );
                          }
                          return GestureDetector(
                            onTap: () =>
                                context.push('/post/${p.id}', extra: p),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Positioned.fill(child: media),
                                if (hasVideo && p.imageUrl.isNotEmpty)
                                  const Align(
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.play_circle_fill_rounded,
                                      color: Colors.white70,
                                      size: 34,
                                    ),
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: PostGridEngagementOverlay(
                                    post: p,
                                    showViewCount: hasVideo,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}
