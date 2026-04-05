import 'dart:io';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

/// Склеивает 2–4 фото в один кадр 9:16 (сетка 2×2 / 2×1).
Future<File?> mergeCollageImages(List<File> files) async {
  if (files.isEmpty) return null;
  if (files.length == 1) return files.first;

  final images = <ui.Image>[];
  try {
    for (final f in files.take(4)) {
      final bytes = await f.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      images.add(frame.image);
    }

    const outW = 1080;
    const outH = 1920;
    final n = images.length;

    var cols = 2;
    var rows = 2;
    if (n == 2) {
      cols = 2;
      rows = 1;
    }

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint()..filterQuality = ui.FilterQuality.high;

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF121212),
    );

    final cellW = outW / cols;
    final cellH = outH / rows;

    for (var i = 0; i < n; i++) {
      final img = images[i];
      final col = i % cols;
      final row = i ~/ cols;
      final dx = col * cellW;
      final dy = row * cellH;
      final src = ui.Rect.fromLTWH(
        0,
        0,
        img.width.toDouble(),
        img.height.toDouble(),
      );
      final dst = ui.Rect.fromLTWH(dx, dy, cellW, cellH);
      canvas.drawImageRect(img, src, dst, paint);
    }

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(outW, outH);
    final byteData =
        await outImage.toByteData(format: ui.ImageByteFormat.png);
    outImage.dispose();
    if (byteData == null) return null;

    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/collage_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await out.writeAsBytes(byteData.buffer.asUint8List());
    return out;
  } finally {
    for (final img in images) {
      img.dispose();
    }
  }
}
