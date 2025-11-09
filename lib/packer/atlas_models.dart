import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'rect.dart';

enum AtlasJsonFormat { array, hash, multi }

class PackerSettings {
  const PackerSettings({
    required this.maxWidth,
    required this.maxHeight,
    required this.padding,
    required this.extrude,
    required this.allowRotation,
    required this.powerOfTwo,
    required this.squareOnly,
    required this.format,
    required this.outputName,
  });

  final int maxWidth;
  final int maxHeight;
  final int padding;
  final int extrude;
  final bool allowRotation;
  final bool powerOfTwo;
  final bool squareOnly;
  final AtlasJsonFormat format;
  final String outputName;

  PackerSettings copyWith({
    int? maxWidth,
    int? maxHeight,
    int? padding,
    int? extrude,
    bool? allowRotation,
    bool? powerOfTwo,
    bool? squareOnly,
    AtlasJsonFormat? format,
    String? outputName,
  }) {
    return PackerSettings(
      maxWidth: maxWidth ?? this.maxWidth,
      maxHeight: maxHeight ?? this.maxHeight,
      padding: padding ?? this.padding,
      extrude: extrude ?? this.extrude,
      allowRotation: allowRotation ?? this.allowRotation,
      powerOfTwo: powerOfTwo ?? this.powerOfTwo,
      squareOnly: squareOnly ?? this.squareOnly,
      format: format ?? this.format,
      outputName: outputName ?? this.outputName,
    );
  }

  static PackerSettings defaults() => const PackerSettings(
    maxWidth: 2048,
    maxHeight: 2048,
    padding: 2,
    extrude: 1,
    allowRotation: true,
    powerOfTwo: true,
    squareOnly: false,
    format: AtlasJsonFormat.array,
    outputName: 'atlas',
  );
}

class SourceSprite {
  SourceSprite({
    required this.path,
    required this.relativeName,
    required this.image,
    required this.trimmed,
    required this.trimRect,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  final String path;
  final String relativeName;
  final img.Image image;
  final img.Image trimmed;
  final RectInt trimRect;
  final int sourceWidth;
  final int sourceHeight;

  int get trimmedWidth => trimmed.width;
  int get trimmedHeight => trimmed.height;
  int get offsetX => trimRect.x;
  int get offsetY => trimRect.y;
}

class PackedSprite {
  const PackedSprite({
    required this.sprite,
    required this.frame,
    required this.rotated,
  });

  final SourceSprite sprite;
  final RectInt frame;
  final bool rotated;
}

class AtlasPage {
  AtlasPage({required this.index, required this.width, required this.height});

  final int index;
  int width;
  int height;
  final List<PackedSprite> sprites = [];
}

class PackingReport {
  const PackingReport({required this.pageImages, required this.diagnostics});

  final List<PagePreview> pageImages;
  final List<String> diagnostics;
}

class PagePreview {
  const PagePreview({
    required this.imageName,
    required this.bytes,
    required this.width,
    required this.height,
    required this.spriteCount,
  });

  final String imageName;
  final Uint8List bytes;
  final int width;
  final int height;
  final int spriteCount;
}
