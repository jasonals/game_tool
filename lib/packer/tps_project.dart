import 'dart:convert';

import 'atlas_models.dart';

class TextureProject {
  TextureProject({required this.settings, this.sourcePath, this.outputPath});

  final PackerSettings settings;
  final String? sourcePath;
  final String? outputPath;

  Map<String, dynamic> toTpsJson() {
    final options = <String, dynamic>{
      'dataFormat': switch (settings.format) {
        AtlasJsonFormat.array => 'json-array',
        AtlasJsonFormat.hash => 'json-hash',
        AtlasJsonFormat.multi => 'json-array',
      },
      'padding': settings.padding,
      'extrude': settings.extrude,
      'allowRotation': settings.allowRotation,
      'maxTextureSize': {
        'width': settings.maxWidth,
        'height': settings.maxHeight,
      },
      'forceSquared': settings.squareOnly,
      'forcePowerOfTwo': settings.powerOfTwo,
      'textureFileName': settings.outputName,
    };

    return {
      'texturePacker': {
        'version': '1.0',
        'fileName': settings.outputName,
        'files': [
          if (sourcePath != null) {'path': sourcePath},
        ],
        'options': options,
        if (outputPath != null) 'outputDir': outputPath,
      },
    };
  }

  String toPrettyString() =>
      const JsonEncoder.withIndent('  ').convert(toTpsJson());

  static TextureProject fromTpsJson(Map<String, dynamic> json) {
    final root = json['texturePacker'] as Map<String, dynamic>? ?? {};
    final options = root['options'] as Map<String, dynamic>? ?? {};
    final files = root['files'] as List<dynamic>?;

    final format = switch (options['dataFormat']) {
      'json-hash' => AtlasJsonFormat.hash,
      'json-array' => AtlasJsonFormat.array,
      'phaser-json-hash' => AtlasJsonFormat.hash,
      'phaser-json-array' => AtlasJsonFormat.array,
      _ => AtlasJsonFormat.array,
    };

    final squareOnly = options['forceSquared'] == true;
    final powerOfTwo = options['forcePowerOfTwo'] != false;
    final maxSize = options['maxTextureSize'] as Map<String, dynamic>?;
    final settings = PackerSettings.defaults().copyWith(
      maxWidth:
          (maxSize?['width'] as num?).toIntSafe() ??
          PackerSettings.defaults().maxWidth,
      maxHeight:
          (maxSize?['height'] as num?).toIntSafe() ??
          PackerSettings.defaults().maxHeight,
      padding:
          (options['padding'] as num?).toIntSafe() ??
          (options['shapePadding'] as num?).toIntSafe() ??
          PackerSettings.defaults().padding,
      extrude:
          (options['extrude'] as num?).toIntSafe() ??
          PackerSettings.defaults().extrude,
      allowRotation:
          options['allowRotation'] as bool? ??
          options['rotation'] as bool? ??
          PackerSettings.defaults().allowRotation,
      powerOfTwo: powerOfTwo,
      squareOnly: squareOnly,
      format: format,
      outputName:
          options['textureFileName'] as String? ??
          root['fileName'] as String? ??
          PackerSettings.defaults().outputName,
    );

    final source = files
        ?.cast<Map<String, dynamic>>()
        .map((entry) => entry['path'] as String?)
        .whereType<String>()
        .firstOrNull;

    final outputDir = root['outputDir'] as String?;

    return TextureProject(
      settings: settings,
      sourcePath: source,
      outputPath: outputDir,
    );
  }

  static TextureProject fromString(String content) {
    final jsonMap = json.decode(content) as Map<String, dynamic>;
    return fromTpsJson(jsonMap);
  }
}

extension on num? {
  int? toIntSafe() => this?.toInt();
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
