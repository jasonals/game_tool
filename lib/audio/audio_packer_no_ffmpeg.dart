import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'audio_models.dart';
import 'wav_processor.dart';

class AudioPackingJob {
  const AudioPackingJob({
    required this.inputPath,
    required this.outputPath,
    required this.settings,
    this.allowedAudios,
  });

  final String inputPath;
  final String outputPath;
  final AudioPackerSettings settings;
  final List<String>? allowedAudios;
}

Future<AudioPackingReport> runAudioPackingJob(AudioPackingJob job) async {
  final diagnostics = <String>[];

  try {
    // Scan directory for WAV files
    diagnostics.add('Scanning for WAV files...');
    final dir = Directory(job.inputPath);
    final audioFiles = <File>[];

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;

      final ext = p.extension(entity.path).toLowerCase();
      if (ext != '.wav') continue;

      final relativePath = p.relative(entity.path, from: job.inputPath);

      // Check if this file is allowed
      if (job.allowedAudios != null) {
        if (!job.allowedAudios!.contains(relativePath)) continue;
      }

      audioFiles.add(entity);
    }

    if (audioFiles.isEmpty) {
      diagnostics.add('No WAV files found');
      diagnostics.add('');
      diagnostics.add('💡 Tip: Only WAV files are supported.');
      diagnostics.add('   Convert your audio files to WAV format first.');
      return AudioPackingReport(
        audioData: null,
        diagnostics: diagnostics,
        totalDuration: 0,
        audioCount: 0,
      );
    }

    audioFiles.sort((a, b) => a.path.compareTo(b.path));
    diagnostics.add('Found ${audioFiles.length} WAV file(s)');

    // Parse WAV files
    diagnostics.add('');
    diagnostics.add('Processing WAV files...');
    final wavFiles = <WavFile>[];
    final soundMap = <String, double>{};
    double currentTime = 0.0;

    for (final file in audioFiles) {
      final relativePath = p.relative(file.path, from: job.inputPath);
      final nameWithoutExt = p
          .basenameWithoutExtension(relativePath)
          .replaceAll(RegExp(r'[^\w\-]'), '_');

      try {
        final wav = WavFile.fromFile(file);

        // Convert format if needed
        final converted = WavConcatenator.convertFormat(
          source: wav,
          targetSampleRate: job.settings.sampleRate,
          targetChannels: 2, // Always use stereo
        );

        wavFiles.add(converted);

        // Store timing info
        soundMap[nameWithoutExt] = currentTime;
        soundMap['${nameWithoutExt}_end'] = currentTime + converted.duration;
        currentTime += converted.duration;

        diagnostics.add(
          '  $nameWithoutExt: ${converted.duration.toStringAsFixed(2)}s '
          '(${converted.sampleRate}Hz, ${converted.numChannels}ch, ${converted.bitsPerSample}bit)',
        );
      } catch (error) {
        diagnostics.add('  ⚠ Failed to process $relativePath: $error');
      }
    }

    if (wavFiles.isEmpty) {
      diagnostics.add('');
      diagnostics.add('No valid WAV files to pack');
      return AudioPackingReport(
        audioData: null,
        diagnostics: diagnostics,
        totalDuration: 0,
        audioCount: 0,
      );
    }

    // Concatenate all WAV files
    diagnostics.add('');
    diagnostics.add('Concatenating audio files...');

    final concatenated = WavConcatenator.concatenate(wavFiles);

    // Write output file
    final outputFileName = '${job.settings.outputName}.wav';
    final outputPath = p.join(job.outputPath, outputFileName);
    final outputFile = File(outputPath);

    concatenated.writeToFile(outputFile);

    // Generate JSON sprite map for Phaser
    final jsonFileName = '${job.settings.outputName}.json';
    final jsonPath = p.join(job.outputPath, jsonFileName);

    final spritemap = <String, dynamic>{};

    for (final key in soundMap.keys) {
      if (key.endsWith('_end')) continue;
      final start = soundMap[key]!;
      final end = soundMap['${key}_end']!;

      spritemap[key] = {
        'start': start,
        'end': end,
        'loop': false,
      };
    }

    final spriteMap = {
      'resources': [outputFileName],
      'spritemap': spritemap,
    };

    File(jsonPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(spriteMap),
    );

    diagnostics.add('✓ Created $outputFileName (${currentTime.toStringAsFixed(2)}s total)');
    diagnostics.add('✓ Created $jsonFileName');
    diagnostics.add('');
    diagnostics.add('Packed ${wavFiles.length} audio files successfully! 🎉');

    final audioData = outputFile.readAsBytesSync();

    return AudioPackingReport(
      audioData: audioData,
      diagnostics: diagnostics,
      totalDuration: currentTime,
      audioCount: wavFiles.length,
    );
  } catch (error, stackTrace) {
    diagnostics.add('');
    diagnostics.add('Error: $error');
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    return AudioPackingReport(
      audioData: null,
      diagnostics: diagnostics,
      totalDuration: 0,
      audioCount: 0,
    );
  }
}

