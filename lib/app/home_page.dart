import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../packer/atlas_models.dart';
import '../packer/packing_job.dart';
import '../packer/sprite_scanner.dart';
import '../packer/tps_project.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _inputDir;
  String? _outputDir;
  PackerSettings _settings = PackerSettings.defaults();
  List<String> _logs = const ['Idle'];
  List<PagePreview> _previews = const [];
  bool _isPacking = false;
  int _selectedPreview = 0;
  bool _isScanningSprites = false;
  List<SpriteEntry> _spriteEntries = const [];

  late final TextEditingController _maxWidthCtrl;
  late final TextEditingController _maxHeightCtrl;
  late final TextEditingController _paddingCtrl;
  late final TextEditingController _extrudeCtrl;
  late final TextEditingController _outputNameCtrl;

  @override
  void initState() {
    super.initState();
    _maxWidthCtrl = TextEditingController(text: '${_settings.maxWidth}');
    _maxHeightCtrl = TextEditingController(text: '${_settings.maxHeight}');
    _paddingCtrl = TextEditingController(text: '${_settings.padding}');
    _extrudeCtrl = TextEditingController(text: '${_settings.extrude}');
    _outputNameCtrl = TextEditingController(text: _settings.outputName);
  }

  @override
  void dispose() {
    _maxWidthCtrl.dispose();
    _maxHeightCtrl.dispose();
    _paddingCtrl.dispose();
    _extrudeCtrl.dispose();
    _outputNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TexturePacker-Style Tool')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PathPicker(
                      label: 'Source folder',
                      path: _inputDir,
                      onPick: _pickInput,
                    ),
                    const SizedBox(height: 12),
                    _PathPicker(
                      label: 'Output folder',
                      path: _outputDir,
                      onPick: _pickOutput,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _loadTps,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Load .tps'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _saveTps,
                          icon: const Icon(Icons.save),
                          label: const Text('Save .tps'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Packing Settings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        _buildNumberField(
                          'Max width',
                          _maxWidthCtrl,
                          (value) => _updateSettings(maxWidth: value),
                        ),
                        _buildNumberField(
                          'Max height',
                          _maxHeightCtrl,
                          (value) => _updateSettings(maxHeight: value),
                        ),
                        _buildNumberField(
                          'Padding',
                          _paddingCtrl,
                          (value) => _updateSettings(padding: value),
                        ),
                        _buildNumberField(
                          'Edge extrude',
                          _extrudeCtrl,
                          (value) => _updateSettings(extrude: value),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _outputNameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Output basename',
                            ),
                            onChanged: (value) {
                              if (value.isEmpty) return;
                              _updateSettings(outputName: value);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<AtlasJsonFormat>(
                            initialValue: _settings.format,
                            decoration: const InputDecoration(
                              labelText: 'JSON format',
                            ),
                            onChanged: (value) {
                              if (value == null) return;
                              _updateSettings(format: value);
                            },
                            items: AtlasJsonFormat.values
                                .map(
                                  (format) => DropdownMenuItem(
                                    value: format,
                                    child: Text(format.name),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        SizedBox(
                          width: 240,
                          child: SwitchListTile.adaptive(
                            title: const Text('Allow 90° rotation'),
                            value: _settings.allowRotation,
                            onChanged: (value) =>
                                _updateSettings(allowRotation: value),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SwitchListTile.adaptive(
                            title: const Text('Power-of-two dimensions'),
                            value: _settings.powerOfTwo,
                            onChanged: (value) =>
                                _updateSettings(powerOfTwo: value),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        SizedBox(
                          width: 240,
                          child: SwitchListTile.adaptive(
                            title: const Text('Square pages only'),
                            value: _settings.squareOnly,
                            onChanged: (value) =>
                                _updateSettings(squareOnly: value),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isPacking ? null : _startPacking,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Pack Atlas'),
                        ),
                        const SizedBox(width: 16),
                        if (_isPacking) const CircularProgressIndicator(),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (context, index) => Text(_logs[index]),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: _PreviewPane(
                        previews: _previews,
                        selectedIndex: _selectedPreview,
                        onSelect: (value) {
                          setState(() {
                            _selectedPreview = value;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Card(
                      child: _SpriteListPanel(
                        sprites: _spriteEntries,
                        isLoading: _isScanningSprites,
                        onToggle: _toggleSprite,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberField(
    String label,
    TextEditingController controller,
    void Function(int value) onChanged,
  ) {
    return SizedBox(
      width: 160,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (value) {
          final parsed = int.tryParse(value);
          if (parsed == null) return;
          onChanged(parsed);
        },
      ),
    );
  }

  Future<void> _pickInput() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Use folder',
      initialDirectory: _inputDir,
    );
    if (path == null) return;
    setState(() {
      _inputDir = path;
    });
    await _refreshSpriteList();
  }

  Future<void> _pickOutput() async {
    final path = await getDirectoryPath(
      confirmButtonText: 'Use folder',
      initialDirectory: _outputDir ?? _inputDir,
    );
    if (path == null) return;
    setState(() {
      _outputDir = path;
    });
  }

  void _updateSettings({
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
    setState(() {
      _settings = _settings.copyWith(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        padding: padding,
        extrude: extrude,
        allowRotation: allowRotation,
        powerOfTwo: powerOfTwo,
        squareOnly: squareOnly,
        format: format,
        outputName: outputName,
      );
      if (maxWidth != null) {
        _maxWidthCtrl.text = '${_settings.maxWidth}';
      }
      if (maxHeight != null) {
        _maxHeightCtrl.text = '${_settings.maxHeight}';
      }
      if (padding != null) {
        _paddingCtrl.text = '${_settings.padding}';
      }
      if (extrude != null) {
        _extrudeCtrl.text = '${_settings.extrude}';
      }
      if (outputName != null && _outputNameCtrl.text != _settings.outputName) {
        _outputNameCtrl.text = _settings.outputName;
      }
    });
  }

  Future<void> _refreshSpriteList() async {
    final dir = _inputDir;
    if (dir == null) {
      setState(() {
        _spriteEntries = const [];
        _isScanningSprites = false;
      });
      return;
    }
    setState(() {
      _isScanningSprites = true;
    });
    try {
      final records = await compute(scanSpriteDirectory, dir);
      if (!mounted) return;
      setState(() {
        _spriteEntries = records
            .map((record) => SpriteEntry(record: record))
            .toList();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to scan sprites: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanningSprites = false;
        });
      }
    }
  }

  void _toggleSprite(int index, bool include) {
    setState(() {
      _spriteEntries = [
        for (var i = 0; i < _spriteEntries.length; i++)
          i == index
              ? _spriteEntries[i].copyWith(included: include)
              : _spriteEntries[i],
      ];
    });
  }

  Future<void> _startPacking() async {
    if (_inputDir == null || _outputDir == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select both source and output folders first.'),
          ),
        );
      }
      return;
    }
    List<String>? allowedSprites;
    if (_spriteEntries.isNotEmpty) {
      final included = _spriteEntries
          .where((entry) => entry.included)
          .map((entry) => entry.record.relativePath)
          .toList();
      if (included.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Select at least one sprite to include before packing.',
              ),
            ),
          );
        }
        return;
      }
      if (included.length != _spriteEntries.length) {
        allowedSprites = included;
      }
    }
    final inputPath = _inputDir!;
    final outputPath = _outputDir!;
    final snapshot = _settings;

    setState(() {
      _isPacking = true;
      _logs = const ['Packing...'];
      _previews = const [];
      _selectedPreview = 0;
    });

    try {
      final job = PackingJob(
        inputPath: inputPath,
        outputPath: outputPath,
        settings: snapshot,
        allowedSprites: allowedSprites,
      );
      final report = await compute(runPackingJob, job);

      setState(() {
        _logs = report.diagnostics;
        _previews = report.pageImages;
        _selectedPreview = report.pageImages.isEmpty
            ? 0
            : _selectedPreview.clamp(0, report.pageImages.length - 1);
      });
    } catch (error, stackTrace) {
      stderr.writeln(error);
      stderr.writeln(stackTrace);
      setState(() {
        _logs = ['Error: $error'];
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Packing failed: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPacking = false;
        });
      }
    }
  }

  Future<void> _loadTps() async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'TexturePacker Project', extensions: ['tps']),
      ],
    );
    if (file == null) return;
    try {
      final content = await file.readAsString();
      final project = TextureProject.fromString(content);
      setState(() {
        _settings = project.settings;
        _inputDir = project.sourcePath ?? _inputDir;
        _outputDir = project.outputPath ?? _outputDir;
        _maxWidthCtrl.text = '${_settings.maxWidth}';
        _maxHeightCtrl.text = '${_settings.maxHeight}';
        _paddingCtrl.text = '${_settings.padding}';
        _extrudeCtrl.text = '${_settings.extrude}';
        _outputNameCtrl.text = _settings.outputName;
      });
      await _refreshSpriteList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded project from ${file.name}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load TPS: $error')));
      }
    }
  }

  Future<void> _saveTps() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'TexturePacker Project', extensions: ['tps']),
      ],
      suggestedName: '${_settings.outputName}.tps',
    );
    if (location == null) return;
    final project = TextureProject(
      settings: _settings,
      sourcePath: _inputDir,
      outputPath: _outputDir,
    );
    try {
      await File(location.path).writeAsString(project.toPrettyString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved project to ${location.path}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save TPS: $error')));
      }
    }
  }
}

class _PathPicker extends StatelessWidget {
  const _PathPicker({
    required this.label,
    required this.path,
    required this.onPick,
  });

  final String label;
  final String? path;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelLarge),
              Text(
                path ?? 'Not selected',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: onPick, child: const Text('Browse')),
      ],
    );
  }
}

class _PreviewPane extends StatelessWidget {
  const _PreviewPane({
    required this.previews,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<PagePreview> previews;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (previews.isEmpty) {
      return const Center(child: Text('Run a pack to see previews.'));
    }
    final index = selectedIndex.clamp(0, previews.length - 1);
    final preview = previews[index];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Preview', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (previews.length > 1)
                DropdownButton<int>(
                  value: index,
                  onChanged: (value) {
                    if (value == null) return;
                    onSelect(value);
                  },
                  items: [
                    for (var i = 0; i < previews.length; i++)
                      DropdownMenuItem(value: i, child: Text('Page ${i + 1}')),
                  ],
                ),
            ],
          ),
          Text(
            '${preview.imageName} • ${preview.width}x${preview.height} • ${preview.spriteCount} sprites',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: preview.width.toDouble(),
                      height: preview.height.toDouble(),
                      child: InteractiveViewer(
                        maxScale: 8,
                        child: Image.memory(
                          preview.bytes,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.none,
                        ),
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

class _SpriteListPanel extends StatelessWidget {
  const _SpriteListPanel({
    required this.sprites,
    required this.isLoading,
    required this.onToggle,
  });

  final List<SpriteEntry> sprites;
  final bool isLoading;
  final void Function(int index, bool include) onToggle;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sprites.isEmpty) {
      return const Center(
        child: Text('Select a source folder to list sprites.'),
      );
    }
    final included = sprites.where((s) => s.included).length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sprites ($included/${sprites.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: sprites.length,
              itemBuilder: (context, index) {
                final entry = sprites[index];
                return CheckboxListTile(
                  value: entry.included,
                  onChanged: (value) {
                    if (value == null) return;
                    onToggle(index, value);
                  },
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  secondary: SizedBox(
                    width: 48,
                    height: 48,
                    child: Image.memory(
                      entry.record.thumbnail,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.none,
                    ),
                  ),
                  title: Text(
                    entry.record.relativePath,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${entry.record.width}×${entry.record.height}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class SpriteEntry {
  const SpriteEntry({required this.record, this.included = true});

  final SpritePreviewRecord record;
  final bool included;

  SpriteEntry copyWith({bool? included}) =>
      SpriteEntry(record: record, included: included ?? this.included);
}
