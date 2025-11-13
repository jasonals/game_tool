import 'dart:typed_data';

enum AudioFormat { wav }

enum AudioOutputFormat { wav }

class AudioPackerSettings {
  const AudioPackerSettings({
    required this.outputName,
    required this.outputFormat,
    required this.bitrate,
    required this.sampleRate,
  });

  final String outputName;
  final AudioOutputFormat outputFormat;
  final int bitrate; // kbps
  final int sampleRate; // Hz

  AudioPackerSettings copyWith({
    String? outputName,
    AudioOutputFormat? outputFormat,
    int? bitrate,
    int? sampleRate,
  }) {
    return AudioPackerSettings(
      outputName: outputName ?? this.outputName,
      outputFormat: outputFormat ?? this.outputFormat,
      bitrate: bitrate ?? this.bitrate,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }

  static AudioPackerSettings defaults() => const AudioPackerSettings(
        outputName: 'audio',
        outputFormat: AudioOutputFormat.wav,
        bitrate: 128,
        sampleRate: 44100,
      );
}

class SourceAudio {
  const SourceAudio({
    required this.path,
    required this.relativeName,
    required this.duration,
    required this.format,
    required this.sizeBytes,
  });

  final String path;
  final String relativeName;
  final double duration; // seconds
  final AudioFormat format;
  final int sizeBytes;
}

class PackedAudio {
  const PackedAudio({
    required this.audio,
    required this.start,
    required this.end,
  });

  final SourceAudio audio;
  final double start; // seconds
  final double end; // seconds
}

class AudioPackingReport {
  const AudioPackingReport({
    required this.audioData,
    required this.diagnostics,
    required this.totalDuration,
    required this.audioCount,
  });

  final Uint8List? audioData;
  final List<String> diagnostics;
  final double totalDuration;
  final int audioCount;
}

class AudioPreviewRecord {
  const AudioPreviewRecord({
    required this.relativePath,
    required this.duration,
    required this.format,
    required this.sizeBytes,
  });

  final String relativePath;
  final double duration;
  final AudioFormat format;
  final int sizeBytes;

  String get formattedSize {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  String get formattedDuration {
    final minutes = (duration / 60).floor();
    final seconds = (duration % 60).toStringAsFixed(1);
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }
}

