import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Карусель фото поста (сеть). Тап — полноэкранный просмотр с зумом.
class PostNetworkPhotoGallery extends StatefulWidget {
  const PostNetworkPhotoGallery({
    super.key,
    required this.urls,
    this.height = 280,
    this.borderRadius = 8,
    this.viewportFraction = 1.0,
  });

  final List<String> urls;
  final double height;
  final double borderRadius;
  final double viewportFraction;

  @override
  State<PostNetworkPhotoGallery> createState() => _PostNetworkPhotoGalleryState();
}

class _PostNetworkPhotoGalleryState extends State<PostNetworkPhotoGallery> {
  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: widget.viewportFraction);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openZoom(int index) {
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (_, _, _) => _NetworkPhotoZoomPage(
          urls: widget.urls,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, index) {
                return _NetworkGallerySlide(
                  url: urls[index],
                  onTap: () => _openZoom(index),
                );
              },
            ),
            if (urls.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(urls.length, (i) {
                    final active = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white54,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Сохраняем страницу карусели в памяти — при свайпе назад картинка не грузится заново с нуля.
class _NetworkGallerySlide extends StatefulWidget {
  const _NetworkGallerySlide({
    required this.url,
    required this.onTap,
  });

  final String url;
  final VoidCallback onTap;

  @override
  State<_NetworkGallerySlide> createState() => _NetworkGallerySlideState();
}

class _NetworkGallerySlideState extends State<_NetworkGallerySlide>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final memW = (MediaQuery.sizeOf(context).width * dpr).round();
    return GestureDetector(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: CachedNetworkImage(
          imageUrl: widget.url,
          fit: BoxFit.cover,
          width: double.infinity,
          memCacheWidth: memW,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (context, url) => ColoredBox(color: Colors.grey.shade900),
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade200,
            alignment: Alignment.center,
            child: Icon(Icons.broken_image_outlined,
                color: Colors.grey.shade500, size: 48),
          ),
        ),
      ),
    );
  }
}

class _NetworkPhotoZoomPage extends StatefulWidget {
  const _NetworkPhotoZoomPage({
    required this.urls,
    required this.initialIndex,
  });

  final List<String> urls;
  final int initialIndex;

  @override
  State<_NetworkPhotoZoomPage> createState() => _NetworkPhotoZoomPageState();
}

class _NetworkPhotoZoomPageState extends State<_NetworkPhotoZoomPage> {
  late PageController _galleryController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _galleryController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            pageController: _galleryController,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: CachedNetworkImageProvider(widget.urls[index]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
                heroAttributes: PhotoViewHeroAttributes(tag: '${widget.urls[index]}_$index'),
              );
            },
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  ),
                  if (widget.urls.length > 1)
                    Expanded(
                      child: Text(
                        '${_index + 1} / ${widget.urls.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Полноэкранный зум для локальных файлов (экран создания поста).
void openLocalPhotoZoom(BuildContext context, List<File> files, int initialIndex) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      pageBuilder: (_, _, _) => _LocalPhotoZoomPage(
        files: files,
        initialIndex: initialIndex.clamp(0, files.length - 1),
      ),
    ),
  );
}

class _LocalPhotoZoomPage extends StatefulWidget {
  const _LocalPhotoZoomPage({
    required this.files,
    required this.initialIndex,
  });

  final List<File> files;
  final int initialIndex;

  @override
  State<_LocalPhotoZoomPage> createState() => _LocalPhotoZoomPageState();
}

class _LocalPhotoZoomPageState extends State<_LocalPhotoZoomPage> {
  late PageController _c;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _c = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            pageController: _c,
            itemCount: widget.files.length,
            onPageChanged: (i) => setState(() => _index = i),
            builder: (context, index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: FileImage(widget.files[index]),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
              );
            },
          ),
          SafeArea(
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            ),
          ),
          if (widget.files.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${_index + 1} / ${widget.files.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
