import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'audio_models.dart';

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
    // Check if ffmpeg is available
    final ffmpegCheck = await Process.run('ffmpeg', ['-version']);
    if (ffmpegCheck.exitCode != 0) {
      throw Exception('ffmpeg is not installed or not in PATH');
    }
    diagnostics.add('✓ ffmpeg found');

    // Scan directory for audio files
    diagnostics.add('Scanning for audio files...');
    final dir = Directory(job.inputPath);
    final audioFiles = <File>[];

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;

      final ext = p.extension(entity.path).toLowerCase();
      if (!['.mp3', '.ogg', '.wav', '.m4a'].contains(ext)) continue;

      final relativePath = p.relative(entity.path, from: job.inputPath);

      // Check if this file is allowed
      if (job.allowedAudios != null) {
        if (!job.allowedAudios!.contains(relativePath)) continue;
      }

      audioFiles.add(entity);
    }

    if (audioFiles.isEmpty) {
      diagnostics.add('No audio files found');
      return AudioPackingReport(
        audioData: null,
        diagnostics: diagnostics,
        totalDuration: 0,
        audioCount: 0,
      );
    }

    audioFiles.sort((a, b) => a.path.compareTo(b.path));
    diagnostics.add('Found ${audioFiles.length} audio file(s)');

    // Create temp directory for processing
    final tempDir = Directory.systemTemp.createTempSync('audio_packer_');
    final normalizedDir = Directory(p.join(tempDir.path, 'normalized'));
    normalizedDir.createSync();

    try {
      // Get durations and normalize all files to same format
      final soundMap = <String, double>{};
      double currentTime = 0.0;

      diagnostics.add('Processing audio files...');

      final normalizedFiles = <String>[];
      for (var i = 0; i < audioFiles.length; i++) {
        final file = audioFiles[i];
        final relativePath = p.relative(file.path, from: job.inputPath);
        final nameWithoutExt = p.basenameWithoutExtension(relativePath)
            .replaceAll(RegExp(r'[^\w\-]'), '_');

        // Get duration using ffprobe
        final probeResult = await Process.run('ffprobe', [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          file.path,
        ]);

        if (probeResult.exitCode != 0) {
          diagnostics.add('⚠ Failed to probe $relativePath');
          continue;
        }

        final duration = double.tryParse(probeResult.stdout.toString().trim());
        if (duration == null) {
          diagnostics.add('⚠ Invalid duration for $relativePath');
          continue;
        }

        // Normalize to wav format for concatenation
        final normalizedPath = p.join(
          normalizedDir.path,
          '${i.toString().padLeft(4, '0')}_$nameWithoutExt.wav',
        );

        final convertResult = await Process.run('ffmpeg', [
          '-i',
          file.path,
          '-ar',
          '${job.settings.sampleRate}',
          '-ac',
          '2', // stereo
          '-y',
          normalizedPath,
        ]);

        if (convertResult.exitCode != 0) {
          diagnostics.add('⚠ Failed to convert $relativePath');
          continue;
        }

        // Store start and end times
        soundMap[nameWithoutExt] = currentTime;
        soundMap['${nameWithoutExt}_end'] = currentTime + duration;

        normalizedFiles.add(normalizedPath);
        currentTime += duration;

        diagnostics.add('  $nameWithoutExt: ${duration.toStringAsFixed(2)}s');
      }

      if (normalizedFiles.isEmpty) {
        diagnostics.add('No valid audio files to pack');
        return AudioPackingReport(
          audioData: null,
          diagnostics: diagnostics,
          totalDuration: 0,
          audioCount: 0,
        );
      }

      // Create concat file list
      final concatListPath = p.join(tempDir.path, 'concat_list.txt');
      final concatContent = normalizedFiles
          .map((path) => "file '${path.replaceAll("'", "'\\''")}'")
          .join('\n');
      File(concatListPath).writeAsStringSync(concatContent);

      // Concatenate all files
      diagnostics.add('Concatenating audio files...');
      final mergedWavPath = p.join(tempDir.path, 'merged.wav');

      final concatResult = await Process.run('ffmpeg', [
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        concatListPath,
        '-c',
        'copy',
        '-y',
        mergedWavPath,
      ]);

      if (concatResult.exitCode != 0) {
        throw Exception('Failed to concatenate audio files');
      }

      // Convert to final format (WAV only now)
      final outputExt = 'wav';
      final outputFileName = '${job.settings.outputName}.$outputExt';
      final outputPath = p.join(job.outputPath, outputFileName);

      diagnostics.add('Encoding to ${outputExt.toUpperCase()}...');

      final encodeArgs = <String>[
        '-i',
        mergedWavPath,
        '-ar',
        '${job.settings.sampleRate}',
        '-ac',
        '2',
      ];

      encodeArgs.addAll(['-y', outputPath]);

      final encodeResult = await Process.run('ffmpeg', encodeArgs);

      if (encodeResult.exitCode != 0) {
        throw Exception('Failed to encode final audio file');
      }

      // Generate JSON sprite map for Phaser
      final jsonFileName = '${job.settings.outputName}.json';
      final jsonPath = p.join(job.outputPath, jsonFileName);

      // Create Phaser-compatible sprite map
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
      diagnostics.add('Packed ${normalizedFiles.length} audio files successfully');

      final audioData = File(outputPath).readAsBytesSync();

      return AudioPackingReport(
        audioData: audioData,
        diagnostics: diagnostics,
        totalDuration: currentTime,
        audioCount: normalizedFiles.length,
      );

    } finally {
      // Clean up temp directory
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {
        // Ignore cleanup errors
      }
    }
  } catch (error, stackTrace) {
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

