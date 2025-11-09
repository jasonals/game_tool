import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'atlas_models.dart';
import 'max_rects_packer.dart';
import 'rect.dart';

class TexturePacker {
  TexturePacker(this.settings);

  final PackerSettings settings;

  Future<PackingReport> packDirectory({
    required Directory inputDir,
    required Directory outputDir,
    Iterable<String>? allowedSprites,
  }) async {
    if (!inputDir.existsSync()) {
      throw Exception('Input directory does not exist: ${inputDir.path}');
    }

    outputDir.createSync(recursive: true);

    final allowedSet = allowedSprites?.toSet();
    final sprites = await _loadSprites(inputDir, allowedSet);
    if (sprites.isEmpty) {
      throw Exception('No PNG files found under ${inputDir.path}');
    }

    var pageWidth = _resolveDimension(settings.maxWidth);
    var pageHeight = _resolveDimension(settings.maxHeight);
    if (settings.squareOnly) {
      final side = math.min(pageWidth, pageHeight);
      pageWidth = side;
      pageHeight = side;
    }

    final pages = _packSprites(
      sprites,
      pageWidth: pageWidth,
      pageHeight: pageHeight,
    );

    if (pages.length > 1 && settings.format != AtlasJsonFormat.multi) {
      throw StateError(
        'Atlas would require ${pages.length} pages. Enable multiatlas output or '
        'increase max size.',
      );
    }

    final diagnostics = <String>[];
    final results = <AtlasPage>[];
    final previews = <PagePreview>[];
    for (final page in pages) {
      final atlasImage = _buildPageImage(page);
      final imageName = _imageNameForPage(page.index);
      final filePath = p.join(outputDir.path, imageName);
      final pngBytes = Uint8List.fromList(img.encodePng(atlasImage));
      File(filePath).writeAsBytesSync(pngBytes);
      diagnostics.add('Wrote $imageName with ${page.sprites.length} sprites');
      results.add(page);
      previews.add(
        PagePreview(
          imageName: imageName,
          bytes: pngBytes,
          width: page.width,
          height: page.height,
          spriteCount: page.sprites.length,
        ),
      );
    }

    final jsonName = settings.format == AtlasJsonFormat.multi
        ? '${settings.outputName}.json'
        : pages.length == 1
        ? '${settings.outputName}.json'
        : '${settings.outputName}_${pages.length}.json';
    final jsonPath = p.join(outputDir.path, jsonName);
    final jsonContent = _buildJson(results);
    File(jsonPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(jsonContent),
      );
    diagnostics.add('Wrote $jsonName');

    return PackingReport(pageImages: previews, diagnostics: diagnostics);
  }

  Future<List<SourceSprite>> _loadSprites(
    Directory dir,
    Set<String>? allowed,
  ) async {
    final sprites = <SourceSprite>[];
    final entries = dir.listSync(recursive: true)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entries) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.png')) continue;
      final bytes = await entity.readAsBytes();
      final decoded = img.decodePng(bytes);
      if (decoded == null) continue;
      final trimRect = _trimRect(decoded);
      final trimmed = img.copyCrop(
        decoded,
        x: trimRect.x,
        y: trimRect.y,
        width: trimRect.width,
        height: trimRect.height,
      );
      final relative = p
          .relative(entity.path, from: dir.path)
          .replaceAll('\\', '/');
      if (allowed != null && !allowed.contains(relative)) {
        continue;
      }
      sprites.add(
        SourceSprite(
          path: entity.path,
          relativeName: relative,
          image: decoded,
          trimmed: trimmed,
          trimRect: trimRect,
          sourceWidth: decoded.width,
          sourceHeight: decoded.height,
        ),
      );
    }
    sprites.sort((a, b) {
      final areaA = a.trimmedWidth * a.trimmedHeight;
      final areaB = b.trimmedWidth * b.trimmedHeight;
      final diff = areaB - areaA;
      return diff != 0 ? diff : a.relativeName.compareTo(b.relativeName);
    });
    return sprites;
  }

  List<AtlasPage> _packSprites(
    List<SourceSprite> sprites, {
    required int pageWidth,
    required int pageHeight,
  }) {
    final remaining = List<SourceSprite>.from(sprites);
    final pages = <AtlasPage>[];
    var pageIndex = 0;

    while (remaining.isNotEmpty) {
      final page = AtlasPage(
        index: pageIndex,
        width: pageWidth,
        height: pageHeight,
      );
      final bin = MaxRectsBin(
        width: pageWidth,
        height: pageHeight,
        allowRotations: settings.allowRotation,
        heuristic: MaxRectsHeuristic.bestShortSide,
      );

      final placedSprites = <SourceSprite>[];
      for (final sprite in remaining) {
        final paddedWidth = sprite.trimmedWidth + settings.padding * 2;
        final paddedHeight = sprite.trimmedHeight + settings.padding * 2;
        final node = bin.insert(paddedWidth, paddedHeight);
        if (node == null) {
          continue;
        }
        final rotated =
            settings.allowRotation &&
            node.width == paddedHeight &&
            node.height == paddedWidth &&
            sprite.trimmedWidth != sprite.trimmedHeight;
        final frame = RectInt(
          x: node.x + settings.padding,
          y: node.y + settings.padding,
          width: rotated ? sprite.trimmedHeight : sprite.trimmedWidth,
          height: rotated ? sprite.trimmedWidth : sprite.trimmedHeight,
        );
        page.sprites.add(
          PackedSprite(sprite: sprite, frame: frame, rotated: rotated),
        );
        placedSprites.add(sprite);
      }

      remaining.removeWhere(placedSprites.contains);
      if (page.sprites.isEmpty) {
        throw StateError(
          'Sprite ${remaining.first.relativeName} does not fit inside ${pageWidth}x$pageHeight page. '
          'Increase max size.',
        );
      }
      _finalizePageSize(page, pageWidth, pageHeight);
      pages.add(page);
      pageIndex++;
    }

    return pages;
  }

  void _finalizePageSize(AtlasPage page, int maxWidth, int maxHeight) {
    var usedWidth = 0;
    var usedHeight = 0;
    for (final packed in page.sprites) {
      usedWidth = math.max(usedWidth, packed.frame.right);
      usedHeight = math.max(usedHeight, packed.frame.bottom);
    }
    final margin =
        settings.padding + math.min(settings.extrude, settings.padding);
    if (usedWidth > 0) {
      usedWidth = math.min(maxWidth, usedWidth + margin).toInt();
    }
    if (usedHeight > 0) {
      usedHeight = math.min(maxHeight, usedHeight + margin).toInt();
    }

    if (settings.squareOnly) {
      final used = math.max(usedWidth, usedHeight);
      final limit = math.min(maxWidth, maxHeight);
      final side = _fitDimension(used, limit);
      page.width = side;
      page.height = side;
    } else {
      page.width = _fitDimension(usedWidth, maxWidth);
      page.height = _fitDimension(usedHeight, maxHeight);
    }
  }

  img.Image _buildPageImage(AtlasPage page) {
    final atlas = img.Image(
      width: page.width,
      height: page.height,
      numChannels: 4,
    );
    atlas.clear(img.ColorUint8.rgba(0, 0, 0, 0));
    for (final packed in page.sprites) {
      final tile = packed.rotated
          ? img.copyRotate(packed.sprite.trimmed, angle: 90)
          : packed.sprite.trimmed;
      img.compositeImage(
        atlas,
        tile,
        dstX: packed.frame.x,
        dstY: packed.frame.y,
        blend: img.BlendMode.direct,
      );
      _extrudeEdges(atlas, packed.frame, settings.extrude);
    }
    return atlas;
  }

  String _imageNameForPage(int index) {
    if (settings.format == AtlasJsonFormat.multi) {
      return '${settings.outputName}-$index.png';
    }
    return index == 0
        ? '${settings.outputName}.png'
        : '${settings.outputName}-$index.png';
  }

  Map<String, dynamic> _buildJson(List<AtlasPage> pages) {
    switch (settings.format) {
      case AtlasJsonFormat.array:
        return _buildArrayJson(pages.single, _imageNameForPage(0));
      case AtlasJsonFormat.hash:
        return _buildHashJson(pages.single, _imageNameForPage(0));
      case AtlasJsonFormat.multi:
        return _buildMultiJson(pages);
    }
  }

  Map<String, dynamic> _framePayload(PackedSprite packed) {
    final sprite = packed.sprite;
    final trimmed =
        sprite.sourceWidth != sprite.trimmedWidth ||
        sprite.sourceHeight != sprite.trimmedHeight;
    return {
      'filename': sprite.relativeName,
      'frame': {
        'x': packed.frame.x,
        'y': packed.frame.y,
        'w': packed.frame.width,
        'h': packed.frame.height,
      },
      'rotated': packed.rotated,
      'trimmed': trimmed,
      'spriteSourceSize': {
        'x': sprite.offsetX,
        'y': sprite.offsetY,
        'w': sprite.trimmedWidth,
        'h': sprite.trimmedHeight,
      },
      'sourceSize': {'w': sprite.sourceWidth, 'h': sprite.sourceHeight},
    };
  }

  Map<String, dynamic> _buildArrayJson(AtlasPage page, String imageName) {
    return {
      'frames': page.sprites.map(_framePayload).toList(),
      'meta': _metaPayload(page, imageName),
    };
  }

  Map<String, dynamic> _buildHashJson(AtlasPage page, String imageName) {
    final frames = <String, dynamic>{};
    for (final packed in page.sprites) {
      frames[packed.sprite.relativeName] = _framePayload(packed);
    }
    return {'frames': frames, 'meta': _metaPayload(page, imageName)};
  }

  Map<String, dynamic> _metaPayload(AtlasPage page, String imageName) => {
    'app': 'game_tool',
    'version': '1.0',
    'image': imageName,
    'scale': '1',
    'size': {'w': page.width, 'h': page.height},
  };

  Map<String, dynamic> _buildMultiJson(List<AtlasPage> pages) {
    return {
      'textures': pages
          .map(
            (page) => {
              'image': _imageNameForPage(page.index),
              'format': 'RGBA8888',
              'size': {'w': page.width, 'h': page.height},
              'scale': 1,
              'frames': page.sprites.map(_framePayload).toList(),
            },
          )
          .toList(),
    };
  }

  RectInt _trimRect(img.Image image) {
    var left = image.width;
    var top = image.height;
    var right = -1;
    var bottom = -1;

    img.Pixel? reusable;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        reusable = image.getPixel(x, y, reusable);
        if (reusable.a == 0) continue;
        if (x < left) left = x;
        if (x > right) right = x;
        if (y < top) top = y;
        if (y > bottom) bottom = y;
      }
    }

    if (right < left || bottom < top) {
      return RectInt(x: 0, y: 0, width: image.width, height: image.height);
    }

    return RectInt(
      x: left,
      y: top,
      width: right - left + 1,
      height: bottom - top + 1,
    );
  }

  int _resolveDimension(int value) {
    if (!settings.powerOfTwo) {
      return value;
    }
    var power = 1;
    while (power < value) {
      power <<= 1;
    }
    return power;
  }

  int _fitDimension(int used, int max) {
    if (max <= 0) {
      return 0;
    }
    used = used.clamp(1, max);
    if (!settings.powerOfTwo) {
      return used;
    }
    var power = 1;
    while (power < used) {
      power <<= 1;
    }
    return power > max ? max : power;
  }

  void _extrudeEdges(img.Image atlas, RectInt frame, int amount) {
    final extrude = math.min(amount, settings.padding);
    if (extrude <= 0) return;

    final left = frame.x;
    final right = frame.right - 1;
    final top = frame.y;
    final bottom = frame.bottom - 1;

    for (var offset = 1; offset <= extrude; offset++) {
      final leftTarget = left - offset;
      final rightTarget = right + offset;
      for (var y = top; y <= bottom; y++) {
        final colorLeft = atlas.getPixel(left, y);
        final colorRight = atlas.getPixel(right, y);
        if (leftTarget >= 0) {
          atlas.setPixel(leftTarget, y, colorLeft);
        }
        if (rightTarget < atlas.width) {
          atlas.setPixel(rightTarget, y, colorRight);
        }
      }

      final topTarget = top - offset;
      final bottomTarget = bottom + offset;
      for (var x = left; x <= right; x++) {
        final colorTop = atlas.getPixel(x, top);
        final colorBottom = atlas.getPixel(x, bottom);
        if (topTarget >= 0) {
          atlas.setPixel(x, topTarget, colorTop);
        }
        if (bottomTarget < atlas.height) {
          atlas.setPixel(x, bottomTarget, colorBottom);
        }
      }

      if (leftTarget >= 0 && topTarget >= 0) {
        atlas.setPixel(leftTarget, topTarget, atlas.getPixel(left, top));
      }
      if (rightTarget < atlas.width && topTarget >= 0) {
        atlas.setPixel(rightTarget, topTarget, atlas.getPixel(right, top));
      }
      if (leftTarget >= 0 && bottomTarget < atlas.height) {
        atlas.setPixel(leftTarget, bottomTarget, atlas.getPixel(left, bottom));
      }
      if (rightTarget < atlas.width && bottomTarget < atlas.height) {
        atlas.setPixel(
          rightTarget,
          bottomTarget,
          atlas.getPixel(right, bottom),
        );
      }
    }
  }
}
