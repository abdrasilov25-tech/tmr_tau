import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

/// Полноэкранный просмотр фото при добавлении/редактировании товара: свайп между снимками, pinch-zoom.
class DraftPhotosViewer extends StatefulWidget {
  const DraftPhotosViewer({
    super.key,
    required this.imageProviders,
    this.initialIndex = 0,
  });

  final List<ImageProvider> imageProviders;
  final int initialIndex;

  /// Открыть просмотр; [imageProviders] не должен быть пустым.
  static Future<void> show(
    BuildContext context, {
    required List<ImageProvider> imageProviders,
    int initialIndex = 0,
  }) {
    if (imageProviders.isEmpty) return Future.value();
    final max = imageProviders.length - 1;
    final i = initialIndex.clamp(0, max);
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (ctx) => DraftPhotosViewer(
        imageProviders: imageProviders,
        initialIndex: i,
      ),
    );
  }

  @override
  State<DraftPhotosViewer> createState() => _DraftPhotosViewerState();
}

class _DraftPhotosViewerState extends State<DraftPhotosViewer> {
  late final PageController _pageController;
  late int _current;

  @override
  void initState() {
    super.initState();
    final max = widget.imageProviders.length - 1;
    final i = widget.initialIndex.clamp(0, max);
    _current = i;
    _pageController = PageController(initialPage: i);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.imageProviders.length;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (BuildContext context, int index) {
              return PhotoViewGalleryPageOptions(
                imageProvider: widget.imageProviders[index],
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 4,
              );
            },
            itemCount: n,
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2,
              ),
            ),
            pageController: _pageController,
            onPageChanged: (i) => setState(() => _current = i),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (n > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        '${_current + 1} / $n',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
