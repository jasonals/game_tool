import 'dart:io';
import 'dart:typed_data';

/// Simple WAV file processor for concatenating audio files
/// Only supports PCM WAV files (most common format)
class WavFile {
  WavFile({
    required this.sampleRate,
    required this.numChannels,
    required this.bitsPerSample,
    required this.audioData,
    this.fileName = '',
  });

  final int sampleRate;
  final int numChannels;
  final int bitsPerSample;
  final Uint8List audioData;
  final String fileName;

  int get numSamples => audioData.length ~/ (numChannels * bitsPerSample ~/ 8);
  double get duration => numSamples / sampleRate;

  static WavFile fromFile(File file) {
    final bytes = file.readAsBytesSync();
    return fromBytes(bytes, fileName: file.path);
  }

  static WavFile fromBytes(Uint8List bytes, {String fileName = ''}) {
    if (bytes.length < 44) {
      throw Exception('File too small to be a valid WAV file');
    }

    final data = ByteData.view(bytes.buffer);

    // Check RIFF header
    final riff = String.fromCharCodes(bytes.sublist(0, 4));
    if (riff != 'RIFF') {
      throw Exception('Not a valid WAV file (missing RIFF header)');
    }

    // Check WAVE format
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    if (wave != 'WAVE') {
      throw Exception('Not a valid WAV file (missing WAVE format)');
    }

    // Find fmt chunk
    var offset = 12;
    while (offset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = data.getUint32(offset + 4, Endian.little);

      if (chunkId == 'fmt ') {
        // Parse format chunk
        final audioFormat = data.getUint16(offset + 8, Endian.little);
        if (audioFormat != 1) {
          throw Exception(
            'Only PCM WAV files are supported (format: $audioFormat)',
          );
        }

        final numChannels = data.getUint16(offset + 10, Endian.little);
        final sampleRate = data.getUint32(offset + 12, Endian.little);
        final bitsPerSample = data.getUint16(offset + 22, Endian.little);

        // Find data chunk
        var dataOffset = offset + 8 + chunkSize;
        while (dataOffset < bytes.length - 8) {
          final dataChunkId = String.fromCharCodes(
            bytes.sublist(dataOffset, dataOffset + 4),
          );
          final dataChunkSize = data.getUint32(
            dataOffset + 4,
            Endian.little,
          );

          if (dataChunkId == 'data') {
            final audioData = bytes.sublist(
              dataOffset + 8,
              dataOffset + 8 + dataChunkSize,
            );
            return WavFile(
              sampleRate: sampleRate,
              numChannels: numChannels,
              bitsPerSample: bitsPerSample,
              audioData: audioData,
              fileName: fileName,
            );
          }

          dataOffset += 8 + dataChunkSize;
          if (dataChunkSize % 2 == 1) dataOffset++; // Padding
        }

        throw Exception('No data chunk found in WAV file');
      }

      offset += 8 + chunkSize;
      if (chunkSize % 2 == 1) offset++; // Padding
    }

    throw Exception('No fmt chunk found in WAV file');
  }

  Uint8List toBytes() {
    final dataSize = audioData.length;
    final fileSize = 36 + dataSize;
    final buffer = Uint8List(44 + dataSize);
    final data = ByteData.view(buffer.buffer);

    // RIFF header
    buffer.setAll(0, 'RIFF'.codeUnits);
    data.setUint32(4, fileSize, Endian.little);
    buffer.setAll(8, 'WAVE'.codeUnits);

    // fmt chunk
    buffer.setAll(12, 'fmt '.codeUnits);
    data.setUint32(16, 16, Endian.little); // fmt chunk size
    data.setUint16(20, 1, Endian.little); // PCM format
    data.setUint16(22, numChannels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    data.setUint32(28, byteRate, Endian.little);
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);

    // data chunk
    buffer.setAll(36, 'data'.codeUnits);
    data.setUint32(40, dataSize, Endian.little);
    buffer.setAll(44, audioData);

    return buffer;
  }

  void writeToFile(File file) {
    file.writeAsBytesSync(toBytes());
  }
}

/// Concatenates multiple WAV files into one
/// All files must have the same format (sample rate, channels, bits per sample)
class WavConcatenator {
  static WavFile concatenate(List<WavFile> wavFiles) {
    if (wavFiles.isEmpty) {
      throw Exception('No WAV files to concatenate');
    }

    final first = wavFiles.first;
    final sampleRate = first.sampleRate;
    final numChannels = first.numChannels;
    final bitsPerSample = first.bitsPerSample;

    // Verify all files have the same format
    for (var i = 1; i < wavFiles.length; i++) {
      final wav = wavFiles[i];
      if (wav.sampleRate != sampleRate ||
          wav.numChannels != numChannels ||
          wav.bitsPerSample != bitsPerSample) {
        throw Exception(
          'All WAV files must have the same format. '
          'File "${wav.fileName}" has different format: '
          '${wav.sampleRate}Hz, ${wav.numChannels}ch, ${wav.bitsPerSample}bit '
          'vs expected ${sampleRate}Hz, ${numChannels}ch, ${bitsPerSample}bit',
        );
      }
    }

    // Calculate total size
    var totalSize = 0;
    for (final wav in wavFiles) {
      totalSize += wav.audioData.length;
    }

    // Concatenate audio data
    final concatenated = Uint8List(totalSize);
    var offset = 0;
    for (final wav in wavFiles) {
      concatenated.setAll(offset, wav.audioData);
      offset += wav.audioData.length;
    }

    return WavFile(
      sampleRate: sampleRate,
      numChannels: numChannels,
      bitsPerSample: bitsPerSample,
      audioData: concatenated,
    );
  }

  /// Converts audio to a specific format by resampling
  /// Note: This is a simple implementation and may not produce high-quality results
  static WavFile convertFormat({
    required WavFile source,
    int? targetSampleRate,
    int? targetChannels,
  }) {
    var result = source;

    // Convert channels if needed
    if (targetChannels != null && targetChannels != source.numChannels) {
      result = _convertChannels(result, targetChannels);
    }

    // Resample if needed
    if (targetSampleRate != null && targetSampleRate != result.sampleRate) {
      result = _resample(result, targetSampleRate);
    }

    return result;
  }

  static WavFile _convertChannels(WavFile source, int targetChannels) {
    if (source.numChannels == targetChannels) return source;

    final bytesPerSample = source.bitsPerSample ~/ 8;
    final sourceChannels = source.numChannels;
    final numFrames = source.audioData.length ~/ (sourceChannels * bytesPerSample);
    final targetData = Uint8List(numFrames * targetChannels * bytesPerSample);

    if (sourceChannels == 2 && targetChannels == 1) {
      // Stereo to mono: average both channels
      for (var i = 0; i < numFrames; i++) {
        final leftOffset = i * 2 * bytesPerSample;
        final rightOffset = leftOffset + bytesPerSample;
        final monoOffset = i * bytesPerSample;

        if (bytesPerSample == 2) {
          // 16-bit audio (signed)
          final left = _readInt16(source.audioData, leftOffset);
          final right = _readInt16(source.audioData, rightOffset);
          final mono = ((left + right) / 2).round();
          _writeInt16(targetData, monoOffset, mono);
        }
      }
    } else if (sourceChannels == 1 && targetChannels == 2) {
      // Mono to stereo: duplicate channel
      for (var i = 0; i < numFrames; i++) {
        final monoOffset = i * bytesPerSample;
        final stereoOffset = i * 2 * bytesPerSample;

        for (var b = 0; b < bytesPerSample; b++) {
          targetData[stereoOffset + b] = source.audioData[monoOffset + b];
          targetData[stereoOffset + bytesPerSample + b] =
              source.audioData[monoOffset + b];
        }
      }
    }

    return WavFile(
      sampleRate: source.sampleRate,
      numChannels: targetChannels,
      bitsPerSample: source.bitsPerSample,
      audioData: targetData,
    );
  }

  // Helper to read signed 16-bit integer from bytes
  static int _readInt16(Uint8List data, int offset) {
    final value = data[offset] | (data[offset + 1] << 8);
    // Convert unsigned to signed
    return value > 0x7FFF ? value - 0x10000 : value;
  }

  // Helper to write signed 16-bit integer to bytes
  static void _writeInt16(Uint8List data, int offset, int value) {
    // Clamp to 16-bit signed range
    final clamped = value.clamp(-32768, 32767);
    // Convert signed to unsigned for storage
    final unsigned = clamped < 0 ? clamped + 0x10000 : clamped;
    data[offset] = unsigned & 0xFF;
    data[offset + 1] = (unsigned >> 8) & 0xFF;
  }

  static WavFile _resample(WavFile source, int targetSampleRate) {
    if (source.sampleRate == targetSampleRate) return source;

    // Simple linear interpolation resampling
    final ratio = source.sampleRate / targetSampleRate;
    final bytesPerSample = source.bitsPerSample ~/ 8;
    final bytesPerFrame = source.numChannels * bytesPerSample;
    final sourceFrames = source.audioData.length ~/ bytesPerFrame;
    final targetFrames = (sourceFrames / ratio).round();
    final targetData = Uint8List(targetFrames * bytesPerFrame);

    for (var i = 0; i < targetFrames; i++) {
      final sourcePos = i * ratio;
      final sourceFrame = sourcePos.floor();
      final frac = sourcePos - sourceFrame;

      if (sourceFrame + 1 < sourceFrames) {
        // Linear interpolation between two frames
        for (var ch = 0; ch < source.numChannels; ch++) {
          final offset1 = (sourceFrame * source.numChannels + ch) * bytesPerSample;
          final offset2 = ((sourceFrame + 1) * source.numChannels + ch) * bytesPerSample;
          final targetOffset = (i * source.numChannels + ch) * bytesPerSample;

          if (bytesPerSample == 2) {
            // 16-bit audio (signed)
            final sample1 = _readInt16(source.audioData, offset1);
            final sample2 = _readInt16(source.audioData, offset2);
            final interpolated = (sample1 + (sample2 - sample1) * frac).round();
            _writeInt16(targetData, targetOffset, interpolated);
          }
        }
      } else {
        // Last frame, just copy
        final offset = (sourceFrame * source.numChannels) * bytesPerSample;
        final targetOffset = (i * source.numChannels) * bytesPerSample;
        for (var b = 0; b < bytesPerFrame; b++) {
          targetData[targetOffset + b] = source.audioData[offset + b];
        }
      }
    }

    return WavFile(
      sampleRate: targetSampleRate,
      numChannels: source.numChannels,
      bitsPerSample: source.bitsPerSample,
      audioData: targetData,
    );
  }
}

