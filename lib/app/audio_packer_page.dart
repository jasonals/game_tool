import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/audio_models.dart';
import '../audio/audio_packer_no_ffmpeg.dart';
import '../audio/audio_scanner.dart';

class AudioPackerPage extends StatefulWidget {
  const AudioPackerPage({super.key});

  @override
  State<AudioPackerPage> createState() => _AudioPackerPageState();
}

class _AudioPackerPageState extends State<AudioPackerPage> {
  String? _inputDir;
  String? _outputDir;
  AudioPackerSettings _settings = AudioPackerSettings.defaults();
  List<String> _logs = const ['Idle'];
  bool _isPacking = false;
  bool _isScanningAudio = false;
  List<AudioEntry> _audioEntries = const [];
  double? _totalDuration;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlaying;
  StreamSubscription<PlayerState>? _playerStateSubscription;

  late final TextEditingController _bitrateCtrl;
  late final TextEditingController _sampleRateCtrl;
  late final TextEditingController _outputNameCtrl;

  @override
  void initState() {
    super.initState();
    _bitrateCtrl = TextEditingController(text: '${_settings.bitrate}');
    _sampleRateCtrl = TextEditingController(text: '${_settings.sampleRate}');
    _outputNameCtrl = TextEditingController(text: _settings.outputName);

    // Listen to player state changes
    _playerStateSubscription = _audioPlayer.onPlayerStateChanged.listen((
      state,
    ) {
      if (state == PlayerState.completed) {
        setState(() {
          _currentlyPlaying = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _bitrateCtrl.dispose();
    _sampleRateCtrl.dispose();
    _outputNameCtrl.dispose();
    _playerStateSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Sprite Packer')),
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
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Theme.of(
                                context,
                              ).colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'WAV files only. Convert your audio to WAV format first.',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
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
                    const SizedBox(height: 24),
                    Text(
                      'Audio Settings',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
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
                        _buildNumberField(
                          'Sample rate (Hz)',
                          _sampleRateCtrl,
                          (value) => _updateSettings(sampleRate: value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isPacking ? null : _startPacking,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('Pack Audio Sprite'),
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
                      child: _AudioListPanel(
                        audioFiles: _audioEntries,
                        isLoading: _isScanningAudio,
                        onToggle: _toggleAudio,
                        totalDuration: _totalDuration,
                        inputDir: _inputDir,
                        onPlay: _playAudio,
                        currentlyPlaying: _currentlyPlaying,
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
      width: 180,
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
    await _refreshAudioList();
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

  void _updateSettings({String? outputName, int? sampleRate}) {
    setState(() {
      _settings = _settings.copyWith(
        outputName: outputName,
        sampleRate: sampleRate,
      );
      if (sampleRate != null) {
        _sampleRateCtrl.text = '${_settings.sampleRate}';
      }
      if (outputName != null && _outputNameCtrl.text != _settings.outputName) {
        _outputNameCtrl.text = _settings.outputName;
      }
    });
  }

  Future<void> _refreshAudioList() async {
    final dir = _inputDir;
    if (dir == null) {
      setState(() {
        _audioEntries = const [];
        _isScanningAudio = false;
      });
      return;
    }
    setState(() {
      _isScanningAudio = true;
    });
    try {
      final records = await compute(scanAudioDirectory, dir);
      if (!mounted) return;
      setState(() {
        _audioEntries = records
            .map((record) => AudioEntry(record: record))
            .toList();
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to scan audio: $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanningAudio = false;
        });
      }
    }
  }

  void _toggleAudio(int index, bool include) {
    setState(() {
      _audioEntries = [
        for (var i = 0; i < _audioEntries.length; i++)
          i == index
              ? _audioEntries[i].copyWith(included: include)
              : _audioEntries[i],
      ];
    });
  }

  Future<void> _playAudio(String relativePath) async {
    if (_inputDir == null) return;

    final fullPath = '$_inputDir/$relativePath';

    // If already playing this file, stop it
    if (_currentlyPlaying == relativePath) {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlaying = null;
      });
      return;
    }

    // Stop any current playback and play new file
    await _audioPlayer.stop();
    setState(() {
      _currentlyPlaying = relativePath;
    });

    try {
      await _audioPlayer.play(DeviceFileSource(fullPath));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to play audio: $error')));
      }
      setState(() {
        _currentlyPlaying = null;
      });
    }
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

    List<String>? allowedAudios;
    if (_audioEntries.isNotEmpty) {
      final included = _audioEntries
          .where((entry) => entry.included)
          .map((entry) => entry.record.relativePath)
          .toList();
      if (included.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Select at least one audio file to include before packing.',
              ),
            ),
          );
        }
        return;
      }
      if (included.length != _audioEntries.length) {
        allowedAudios = included;
      }
    }

    final inputPath = _inputDir!;
    final outputPath = _outputDir!;
    final snapshot = _settings;

    setState(() {
      _isPacking = true;
      _logs = const ['Packing audio...'];
      _totalDuration = null;
    });

    try {
      final job = AudioPackingJob(
        inputPath: inputPath,
        outputPath: outputPath,
        settings: snapshot,
        allowedAudios: allowedAudios,
      );
      final report = await compute(runAudioPackingJob, job);

      setState(() {
        _logs = report.diagnostics;
        _totalDuration = report.totalDuration;
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

class _AudioListPanel extends StatelessWidget {
  const _AudioListPanel({
    required this.audioFiles,
    required this.isLoading,
    required this.onToggle,
    this.totalDuration,
    this.inputDir,
    required this.onPlay,
    this.currentlyPlaying,
  });

  final List<AudioEntry> audioFiles;
  final bool isLoading;
  final void Function(int index, bool include) onToggle;
  final double? totalDuration;
  final String? inputDir;
  final Future<void> Function(String relativePath) onPlay;
  final String? currentlyPlaying;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (audioFiles.isEmpty) {
      return const Center(
        child: Text('Select a source folder to list audio files.'),
      );
    }

    final included = audioFiles.where((s) => s.included).length;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Audio Files ($included/${audioFiles.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              if (totalDuration != null)
                Text(
                  'Total: ${totalDuration!.toStringAsFixed(2)}s',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: audioFiles.length,
              itemBuilder: (context, index) {
                final entry = audioFiles[index];
                final isPlaying = currentlyPlaying == entry.record.relativePath;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: entry.included,
                          onChanged: (value) {
                            if (value == null) return;
                            onToggle(index, value);
                          },
                        ),
                        Icon(
                          _getFormatIcon(entry.record.format),
                          size: 32,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                entry.record.relativePath,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                '${entry.record.formattedSize} • ${entry.record.format.name.toUpperCase()}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isPlaying ? Icons.stop : Icons.play_arrow,
                            color: isPlaying
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: inputDir == null
                              ? null
                              : () => onPlay(entry.record.relativePath),
                          tooltip: isPlaying ? 'Stop' : 'Play',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getFormatIcon(AudioFormat format) {
    switch (format) {
      case AudioFormat.wav:
        return Icons.graphic_eq;
    }
  }
}

class AudioEntry {
  const AudioEntry({required this.record, this.included = true});

  final AudioPreviewRecord record;
  final bool included;

  AudioEntry copyWith({bool? included}) =>
      AudioEntry(record: record, included: included ?? this.included);
}
