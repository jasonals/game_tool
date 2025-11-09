import 'dart:convert';

import 'package:xml/xml.dart';

import 'atlas_models.dart';

enum ProjectFileFormat { json, xml }

class TextureProject {
  TextureProject({
    required this.settings,
    this.sourcePath,
    this.outputPath,
    this.projectFormat = ProjectFileFormat.xml,
    XmlDocument? xmlDocument,
  }) : _xmlDocument = xmlDocument;

  final PackerSettings settings;
  final String? sourcePath;
  final String? outputPath;
  final ProjectFileFormat projectFormat;
  final XmlDocument? _xmlDocument;

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

  String toPrettyString() => switch (projectFormat) {
    ProjectFileFormat.json => const JsonEncoder.withIndent(
      '  ',
    ).convert(toTpsJson()),
    ProjectFileFormat.xml => _buildXmlString(),
  };

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
    final defaults = PackerSettings.defaults();
    final settings = defaults.copyWith(
      maxWidth: _toIntSafe(maxSize?['width'] as num?) ?? defaults.maxWidth,
      maxHeight: _toIntSafe(maxSize?['height'] as num?) ?? defaults.maxHeight,
      padding:
          _toIntSafe(options['padding'] as num?) ??
          _toIntSafe(options['shapePadding'] as num?) ??
          defaults.padding,
      extrude: _toIntSafe(options['extrude'] as num?) ?? defaults.extrude,
      allowRotation:
          options['allowRotation'] as bool? ??
          options['rotation'] as bool? ??
          defaults.allowRotation,
      powerOfTwo: powerOfTwo,
      squareOnly: squareOnly,
      format: format,
      outputName:
          options['textureFileName'] as String? ??
          root['fileName'] as String? ??
          defaults.outputName,
    );

    final sourceIterable = files
        ?.cast<Map<String, dynamic>>()
        .map((entry) => entry['path'] as String?)
        .whereType<String>();
    final source = sourceIterable == null ? null : _firstOrNull(sourceIterable);

    final outputDir = root['outputDir'] as String?;

    return TextureProject(
      settings: settings,
      sourcePath: source,
      outputPath: outputDir,
      projectFormat: ProjectFileFormat.json,
    );
  }

  static TextureProject fromString(String content) {
    final trimmed = content.trimLeft();
    if (trimmed.startsWith('{')) {
      final jsonMap = json.decode(content) as Map<String, dynamic>;
      return fromTpsJson(jsonMap);
    }
    if (trimmed.startsWith('<')) {
      return fromTpsXml(content);
    }
    throw FormatException('Unsupported TPS format');
  }

  static TextureProject fromTpsXml(String content) {
    final document = XmlDocument.parse(content);
    final settingsStruct = document
        .findAllElements('struct')
        .firstWhere((node) => node.getAttribute('type') == 'Settings');
    final map = _parseStruct(settingsStruct);

    final algorithm = map['algorithmSettings'] as Map<String, dynamic>? ?? {};
    final globalSpriteSettings =
        map['globalSpriteSettings'] as Map<String, dynamic>? ?? {};
    final maxTextureSize = map['maxTextureSize'] as Map<String, dynamic>? ?? {};
    final fileLists = map['fileLists'] as Map<String, dynamic>? ?? {};
    final defaultList = fileLists['default'] as Map<String, dynamic>? ?? {};
    final files = defaultList['files'] as List<dynamic>? ?? const [];
    final firstFile = _firstOrNull(files.whereType<String>());

    final textureSubPath = map['textureSubPath'] as String?;

    final sizeConstraints = (algorithm['sizeConstraints'] as String?) ?? '';
    final powerOfTwo = sizeConstraints.toLowerCase().contains('power');
    final squareOnly = algorithm['forceSquared'] as bool? ?? false;

    final defaults = PackerSettings.defaults();
    final padding = _toIntSafe(map['shapePadding'] as num?) ?? defaults.padding;
    final extrude =
        _toIntSafe(globalSpriteSettings['extrude'] as num?) ?? defaults.extrude;
    final allowRotation =
        map['allowRotation'] as bool? ?? defaults.allowRotation;
    final outputName =
        (map['textureFileName'] as String?) ?? defaults.outputName;
    final dataFormat = (map['dataFormat'] as String?) ?? 'phaser';

    final format = _formatFromDataFormat(dataFormat);

    final settings = defaults.copyWith(
      maxWidth:
          _toIntSafe(maxTextureSize['width'] as num?) ?? defaults.maxWidth,
      maxHeight:
          _toIntSafe(maxTextureSize['height'] as num?) ?? defaults.maxHeight,
      padding: padding,
      extrude: extrude,
      allowRotation: allowRotation,
      powerOfTwo: powerOfTwo,
      squareOnly: squareOnly,
      format: format,
      outputName: outputName.isEmpty ? defaults.outputName : outputName,
    );

    return TextureProject(
      settings: settings,
      sourcePath: firstFile == null || firstFile.isEmpty || firstFile == '.'
          ? null
          : firstFile,
      outputPath: textureSubPath?.isEmpty ?? true ? null : textureSubPath,
      projectFormat: ProjectFileFormat.xml,
      xmlDocument: document,
    );
  }

  String _buildXmlString() {
    final document = (_xmlDocument ?? _buildTemplateDocument()).copy();
    final settingsStruct = document
        .findAllElements('struct')
        .firstWhere((node) => node.getAttribute('type') == 'Settings');

    _setScalar(
      settingsStruct,
      'allowRotation',
      _boolElement(settings.allowRotation),
    );
    _setScalar(
      settingsStruct,
      'dataFormat',
      _stringElement(_dataFormatFor(settings.format)),
    );
    _setScalar(
      settingsStruct,
      'textureFileName',
      _filenameElement(settings.outputName),
    );
    _setScalar(settingsStruct, 'shapePadding', _uintElement(settings.padding));
    _setScalar(
      settingsStruct,
      'textureSubPath',
      _stringElement(outputPath ?? ''),
    );

    final maxTexture = _ensureStruct(settingsStruct, 'maxTextureSize', 'QSize');
    _setScalar(maxTexture, 'width', _intElement(settings.maxWidth));
    _setScalar(maxTexture, 'height', _intElement(settings.maxHeight));

    final algorithmStruct = _ensureStruct(
      settingsStruct,
      'algorithmSettings',
      'AlgorithmSettings',
    );
    _setScalar(
      algorithmStruct,
      'forceSquared',
      _boolElement(settings.squareOnly),
    );
    _setScalar(
      algorithmStruct,
      'sizeConstraints',
      _enumElement(
        'AlgorithmSettings::SizeConstraints',
        settings.powerOfTwo ? 'PowerOfTwo' : 'AnySize',
      ),
    );

    final globalSpriteStruct = _ensureStruct(
      settingsStruct,
      'globalSpriteSettings',
      'SpriteSettings',
    );
    _setScalar(globalSpriteStruct, 'extrude', _uintElement(settings.extrude));

    final fileListsStruct = _ensureStruct(
      settingsStruct,
      'fileLists',
      'SpriteSheetMap',
    );
    final defaultStruct = _ensureStruct(
      fileListsStruct,
      'default',
      'SpriteSheet',
    );
    final filesArray = _ensureArray(defaultStruct, 'files');
    filesArray.children
      ..clear()
      ..add(
        XmlElement(XmlName('filename'), [], [
          XmlText(
            sourcePath == null || sourcePath!.isEmpty ? '.' : sourcePath!,
          ),
        ]),
      );

    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..write(document.toXmlString(pretty: true, indent: '    '));
    return buffer.toString();
  }

  XmlElement _ensureStruct(XmlElement parent, String key, String type) {
    final value = _valueForKey(parent, key);
    if (value is XmlElement && value.name.local == 'struct') {
      return value;
    }
    final struct = XmlElement(XmlName('struct'), [
      XmlAttribute(XmlName('type'), type),
    ]);
    _setScalar(parent, key, struct);
    return struct;
  }

  XmlElement _ensureArray(XmlElement parent, String key) {
    final value = _valueForKey(parent, key);
    if (value is XmlElement && value.name.local == 'array') {
      return value;
    }
    final array = XmlElement(XmlName('array'));
    _setScalar(parent, key, array);
    return array;
  }

  void _setScalar(XmlElement struct, String key, XmlElement replacement) {
    final pair = _valueNodePair(struct, key);
    if (pair != null) {
      pair.value.replace(replacement);
      return;
    }
    struct.children.add(XmlElement(XmlName('key'), [], [XmlText(key)]));
    struct.children.add(replacement);
  }

  XmlElement? _valueForKey(XmlElement struct, String key) =>
      _valueNodePair(struct, key)?.value;

  _KeyValuePair? _valueNodePair(XmlElement struct, String target) {
    final children = struct.children.toList();
    for (var i = 0; i < children.length; i++) {
      final node = children[i];
      if (node is XmlElement && node.name.local == 'key') {
        if (node.innerText.trim() == target) {
          for (var j = i + 1; j < children.length; j++) {
            final candidate = children[j];
            if (candidate is XmlElement) {
              return _KeyValuePair(node, candidate);
            }
          }
        }
      }
    }
    return null;
  }

  static XmlElement _boolElement(bool value) =>
      XmlElement(XmlName(value ? 'true' : 'false'));

  static XmlElement _stringElement(String value) =>
      XmlElement(XmlName('string'), [], [XmlText(value)]);

  static XmlElement _filenameElement(String value) =>
      XmlElement(XmlName('filename'), [], [XmlText(value)]);

  static XmlElement _intElement(int value) =>
      XmlElement(XmlName('int'), [], [XmlText('$value')]);

  static XmlElement _uintElement(int value) =>
      XmlElement(XmlName('uint'), [], [XmlText('$value')]);

  static XmlElement _enumElement(String type, String value) => XmlElement(
    XmlName('enum'),
    [XmlAttribute(XmlName('type'), type)],
    [XmlText(value)],
  );

  static XmlDocument _buildTemplateDocument() {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element(
      'data',
      attributes: {'version': '1.0'},
      nest: () {
        builder.element(
          'struct',
          attributes: {'type': 'Settings'},
          nest: () {
            _writeKeyValue(builder, 'fileFormatVersion', () {
              builder.element('int', nest: () => builder.text('6'));
            });
            _writeKeyValue(builder, 'texturePackerVersion', () {
              builder.element('string', nest: () => builder.text('7.9.1'));
            });
            _writeKeyValue(builder, 'autoSDSettings', () {
              builder.element(
                'array',
                nest: () {
                  builder.element(
                    'struct',
                    attributes: {'type': 'AutoSDSettings'},
                    nest: () {
                      _writeKeyValue(builder, 'scale', () {
                        builder.element(
                          'double',
                          nest: () => builder.text('1'),
                        );
                      });
                      _writeKeyValue(builder, 'extension', () {
                        builder.element('string', nest: () => builder.text(''));
                      });
                      _writeKeyValue(builder, 'spriteFilter', () {
                        builder.element('string', nest: () => builder.text(''));
                      });
                      _writeKeyValue(builder, 'acceptFractionalValues', () {
                        builder.element('false');
                      });
                      _writeKeyValue(builder, 'maxTextureSize', () {
                        builder.element(
                          'QSize',
                          nest: () {
                            _writeKeyValue(builder, 'width', () {
                              builder.element(
                                'int',
                                nest: () => builder.text('-1'),
                              );
                            });
                            _writeKeyValue(builder, 'height', () {
                              builder.element(
                                'int',
                                nest: () => builder.text('-1'),
                              );
                            });
                          },
                        );
                      });
                    },
                  );
                },
              );
            });
            _writeKeyValue(builder, 'allowRotation', () {
              builder.element('true');
            });
            _writeKeyValue(builder, 'dataFormat', () {
              builder.element('string', nest: () => builder.text('phaser'));
            });
            _writeKeyValue(builder, 'textureFileName', () {
              builder.element('filename', nest: () => builder.text('atlas'));
            });
            _writeKeyValue(builder, 'shapePadding', () {
              builder.element('uint', nest: () => builder.text('2'));
            });
            _writeKeyValue(builder, 'textureSubPath', () {
              builder.element('string', nest: () => builder.text(''));
            });
            _writeKeyValue(builder, 'maxTextureSize', () {
              builder.element(
                'QSize',
                nest: () {
                  _writeKeyValue(builder, 'width', () {
                    builder.element('int', nest: () => builder.text('2048'));
                  });
                  _writeKeyValue(builder, 'height', () {
                    builder.element('int', nest: () => builder.text('2048'));
                  });
                },
              );
            });
            _writeKeyValue(builder, 'algorithmSettings', () {
              builder.element(
                'struct',
                attributes: {'type': 'AlgorithmSettings'},
                nest: () {
                  _writeKeyValue(builder, 'forceSquared', () {
                    builder.element('false');
                  });
                  _writeKeyValue(builder, 'sizeConstraints', () {
                    builder.element(
                      'enum',
                      attributes: {
                        'type': 'AlgorithmSettings::SizeConstraints',
                      },
                      nest: () => builder.text('AnySize'),
                    );
                  });
                },
              );
            });
            _writeKeyValue(builder, 'globalSpriteSettings', () {
              builder.element(
                'struct',
                attributes: {'type': 'SpriteSettings'},
                nest: () {
                  _writeKeyValue(builder, 'extrude', () {
                    builder.element('uint', nest: () => builder.text('1'));
                  });
                },
              );
            });
            _writeKeyValue(builder, 'fileLists', () {
              builder.element(
                'map',
                attributes: {'type': 'SpriteSheetMap'},
                nest: () {
                  _writeKeyValue(builder, 'default', () {
                    builder.element(
                      'struct',
                      attributes: {'type': 'SpriteSheet'},
                      nest: () {
                        _writeKeyValue(builder, 'files', () {
                          builder.element(
                            'array',
                            nest: () {
                              builder.element(
                                'filename',
                                nest: () => builder.text('.'),
                              );
                            },
                          );
                        });
                      },
                    );
                  });
                },
              );
            });
            _writeKeyValue(builder, 'ignoreFileList', () {
              builder.element('array');
            });
            _writeKeyValue(builder, 'replaceList', () {
              builder.element('array');
            });
          },
        );
      },
    );
    return builder.buildDocument();
  }

  static void _writeKeyValue(
    XmlBuilder builder,
    String key,
    void Function() writeValue,
  ) {
    builder.element('key', nest: () => builder.text(key));
    writeValue();
  }

  static Map<String, dynamic> _parseStruct(XmlElement struct) {
    final map = <String, dynamic>{};
    final children = struct.children.whereType<XmlElement>().toList();
    for (var i = 0; i < children.length; i++) {
      final node = children[i];
      if (node.name.local != 'key') continue;
      final key = node.innerText.trim();
      if (key.isEmpty) continue;
      XmlElement? value;
      for (var j = i + 1; j < children.length && value == null; j++) {
        final candidate = children[j];
        if (candidate.name.local == 'key') break;
        value = candidate;
      }
      if (value == null) continue;
      map[key] = _parseValue(value);
    }
    return map;
  }

  static dynamic _parseValue(XmlElement element) {
    final name = element.name.local;
    switch (name) {
      case 'int':
      case 'uint':
        return int.tryParse(
              element.innerText.trim().isEmpty ? '0' : element.innerText.trim(),
            ) ??
            0;
      case 'double':
        return double.tryParse(element.innerText.trim()) ?? 0;
      case 'string':
      case 'filename':
      case 'rect':
      case 'point_f':
        return element.innerText;
      case 'true':
        return true;
      case 'false':
        return false;
      case 'enum':
        return element.innerText;
      case 'array':
        return element.children
            .whereType<XmlElement>()
            .map(_parseValue)
            .toList();
      case 'struct':
      case 'QSize':
      case 'map':
        return _parseStruct(element);
      default:
        return element.innerText;
    }
  }

  static AtlasJsonFormat _formatFromDataFormat(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('hash')) {
      return AtlasJsonFormat.hash;
    }
    return AtlasJsonFormat.array;
  }

  static String _dataFormatFor(AtlasJsonFormat format) => switch (format) {
    AtlasJsonFormat.hash => 'json-hash',
    AtlasJsonFormat.array => 'phaser',
    AtlasJsonFormat.multi => 'phaser',
  };
}

class _KeyValuePair {
  _KeyValuePair(this.key, this.value);

  final XmlElement key;
  final XmlElement value;
}

int? _toIntSafe(num? value) => value?.toInt();

T? _firstOrNull<T>(Iterable<T> items) => items.isEmpty ? null : items.first;
