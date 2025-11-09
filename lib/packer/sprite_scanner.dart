import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

class SpritePreviewRecord {
  const SpritePreviewRecord({
    required this.relativePath,
    required this.width,
    required this.height,
    required this.thumbnail,
  });

  final String relativePath;
  final int width;
  final int height;
  final Uint8List thumbnail;
}

Future<List<SpritePreviewRecord>> scanSpriteDirectory(String dirPath) async {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    return const [];
  }
  final entries = dir.listSync(recursive: true)
    ..sort((a, b) => a.path.compareTo(b.path));
  final previews = <SpritePreviewRecord>[];
  for (final entity in entries) {
    if (entity is! File) continue;
    if (!entity.path.toLowerCase().endsWith('.png')) continue;
    final bytes = await entity.readAsBytes();
    final decoded = img.decodePng(bytes);
    if (decoded == null) continue;
    final thumb = _buildThumbnail(decoded);
    final relative = p
        .relative(entity.path, from: dir.path)
        .replaceAll('\\', '/');
    previews.add(
      SpritePreviewRecord(
        relativePath: relative,
        width: decoded.width,
        height: decoded.height,
        thumbnail: thumb,
      ),
    );
  }
  return previews;
}

Uint8List _buildThumbnail(img.Image source) {
  const maxSide = 96;
  final resized = img.copyResize(
    source,
    width: source.width > source.height ? maxSide : null,
    height: source.height >= source.width ? maxSide : null,
  );
  return Uint8List.fromList(img.encodePng(resized));
}
