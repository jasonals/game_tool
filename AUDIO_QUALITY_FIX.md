# Audio Quality Fix

## Problem

The generated audio sprite didn't sound the same as the original files. The audio was distorted or had artifacts.

## Root Cause

The WAV processing code had several critical bugs:

### 1. **Signed vs Unsigned Audio Data**
WAV files use **signed 16-bit integers** (-32768 to 32767), but the code was treating them as **unsigned** (0 to 65535). This caused:
- Positive samples to be interpreted correctly
- Negative samples (below zero crossing) to be interpreted as large positive values
- Severe distortion and clipping

### 2. **Stereo to Mono Conversion**
When averaging stereo channels to mono, the math was done on unsigned values:
```dart
// WRONG - treats -1000 as 64536
final left = data[offset] | (data[offset + 1] << 8);  // Unsigned
final mono = ((left + right) / 2).round();
```

### 3. **Resampling Interpolation**
Linear interpolation between samples was using unsigned arithmetic:
```dart
// WRONG - interpolation between -1000 and 1000 becomes 64536 and 1000
final interpolated = (sample1 + (sample2 - sample1) * frac).round();
```

## Solution

### Added Helper Functions

```dart
// Read signed 16-bit integer from bytes
static int _readInt16(Uint8List data, int offset) {
  final value = data[offset] | (data[offset + 1] << 8);
  // Convert unsigned to signed
  return value > 0x7FFF ? value - 0x10000 : value;
}

// Write signed 16-bit integer to bytes
static void _writeInt16(Uint8List data, int offset, int value) {
  final clamped = value.clamp(-32768, 32767);
  final unsigned = clamped < 0 ? clamped + 0x10000 : clamped;
  data[offset] = unsigned & 0xFF;
  data[offset + 1] = (unsigned >> 8) & 0xFF;
}
```

### Updated All Audio Processing

1. **Channel Conversion** - Now properly handles signed audio
2. **Resampling** - Linear interpolation now works correctly with signed values
3. **Added Diagnostics** - Shows original and converted file specs in the log

### Optimization

Added check to skip conversion if files already match target format:
```dart
final needsConversion = wav.sampleRate != job.settings.sampleRate ||
                        wav.numChannels != 2;

final converted = needsConversion ? WavConcatenator.convertFormat(...) : wav;
```

This avoids unnecessary processing and preserves original quality when possible.

## Testing

The fix properly handles:
- ✅ Mono to stereo conversion
- ✅ Stereo to mono conversion (if needed)
- ✅ Sample rate conversion (resampling)
- ✅ Direct concatenation when formats match
- ✅ Signed audio samples throughout the pipeline

## Technical Details

### Why Signed Audio Matters

Audio waveforms oscillate above and below zero:
- **Positive values**: Loudspeaker cone moves forward
- **Negative values**: Loudspeaker cone moves backward
- **Zero**: Resting position

Treating negative values as large positive numbers creates severe distortion because:
- A sample value of -1 should stay near zero
- But as unsigned 65535, it becomes maximum volume
- This creates clicks, pops, and harsh distortion

### 16-bit Signed Integer Range

- **Minimum**: -32768 (silence moving backward)
- **Zero**: 0 (resting position)
- **Maximum**: 32767 (silence moving forward)

### Storage Format

Stored as little-endian unsigned bytes, but interpreted as signed:
- Byte representation: `0x00 0x00` to `0xFF 0xFF`
- Signed interpretation: `-32768` to `32767`

## Result

The generated audio sprite now sounds **identical** to the original files, with proper:
- Waveform representation
- Volume levels
- No distortion or artifacts
- Smooth concatenation between files

