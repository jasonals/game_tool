import 'dart:io';

import 'package:path/path.dart' as p;

import 'audio_models.dart';

const _supportedExtensions = {'.wav'};

AudioFormat? _extensionToFormat(String ext) {
  switch (ext.toLowerCase()) {
    case '.wav':
      return AudioFormat.wav;
    default:
      return null;
  }
}

Future<List<AudioPreviewRecord>> scanAudioDirectory(String dirPath) async {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    throw Exception('Directory does not exist: $dirPath');
  }

  final records = <AudioPreviewRecord>[];
  final entities = dir.listSync(recursive: true);

  for (final entity in entities) {
    if (entity is! File) continue;

    final ext = p.extension(entity.path).toLowerCase();
    if (!_supportedExtensions.contains(ext)) continue;

    final format = _extensionToFormat(ext);
    if (format == null) continue;

    final relativePath = p.relative(entity.path, from: dirPath);
    final stat = entity.statSync();

    // For now, we can't easily get duration without ffprobe or similar
    // We'll estimate or leave as 0 until we process
    final record = AudioPreviewRecord(
      relativePath: relativePath,
      duration: 0.0, // Will be updated during actual processing
      format: format,
      sizeBytes: stat.size,
    );

    records.add(record);
  }

  records.sort((a, b) => a.relativePath.compareTo(b.relativePath));
  return records;
}

