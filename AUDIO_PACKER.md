# Audio Sprite Packer

The Audio Sprite Packer tool converts and concatenates multiple audio files into a single audio file with a companion JSON file for use with Phaser's audio sprite system.

## Features

- **WAV Format Support**: Input and output in WAV format
- **No External Dependencies**: Pure Dart implementation - no ffmpeg required!
- **Audio Preview**: Play/stop sounds directly in the app before packing
- **Quality Control**: Adjustable sample rate
- **Format Conversion**: Automatically converts different WAV formats to a consistent output
- **Phaser Integration**: Generates JSON file compatible with Phaser's audio sprite loader
- **File Selection**: Choose which audio files to include in the pack

## Requirements

**No external dependencies!** Everything is built-in. Just make sure your audio files are in WAV format.

### Converting to WAV

If you have audio in other formats (MP3, OGG, M4A), convert them to WAV first using:

- **Online converters**: CloudConvert, Online-Convert, etc.
- **macOS**: `afconvert input.mp3 output.wav -d LEI16@44100`
- **ffmpeg** (if installed): `ffmpeg -i input.mp3 output.wav`
- **Audacity**: Free audio editor that can convert to WAV

## Usage

1. **Convert audio to WAV** (if needed)
2. **Select Source Folder**: Choose the folder containing your WAV files
3. **Select Output Folder**: Choose where to save the packed audio and JSON
4. **Configure Settings**:
   - **Output basename**: Name for the output files (default: "audio")
   - **Sample rate**: Audio sample rate in Hz (default: 44100)
5. **Preview Audio**: Click the play button (▶) next to any file to preview it
6. **Select Files**: Check/uncheck audio files to include
7. **Pack**: Click "Pack Audio Sprite" to generate the output

## Output Files

The packer generates two files:

1. **Audio file** (`<basename>.wav`): Contains all selected audio files concatenated
2. **JSON file** (`<basename>.json`): Contains timing information for each sound

### JSON Format

```json
{
  "resources": ["audio.wav"],
  "spritemap": {
    "sound1": {
      "start": 0.0,
      "end": 2.5,
      "loop": false
    },
    "sound2": {
      "start": 2.5,
      "end": 5.3,
      "loop": false
    }
  }
}
```

## Using with Phaser

Load the audio sprite in Phaser:

```javascript
// In preload()
this.load.audioSprite('sounds', 'audio.json');

// In create() or anywhere
this.sound.playAudioSprite('sounds', 'sound1');
```

Note: Phaser supports WAV format natively. If you need compressed formats for web deployment, you can convert the final WAV output to OGG/MP3 using online tools or ffmpeg.

## Technical Details

### Supported WAV Formats

- PCM (uncompressed) WAV files only
- Any sample rate (automatically resampled to target)
- Mono or Stereo (automatically converted to stereo output)
- 16-bit audio (most common)

### Processing

1. All input WAV files are read and validated
2. Files are automatically resampled to the target sample rate
3. Mono files are converted to stereo
4. Audio data is concatenated in alphabetical order by filename
5. Single WAV file and JSON metadata are written

### Performance

- Processing is done in a background isolate to keep UI responsive
- Pure Dart implementation is fast for reasonable file sizes
- No subprocess overhead or external dependencies

## Notes

- Audio files are processed in alphabetical order by filename
- All audio is converted to stereo (2 channels) for consistency
- File names are sanitized (non-alphanumeric characters replaced with underscores)
- WAV format works well for desktop games; for web games, consider converting the final output to OGG for better compression

## Why WAV Only?

WAV format was chosen because:
- **Simple format**: Easy to parse and manipulate in pure Dart
- **No licensing issues**: No patent/codec concerns
- **Universal support**: All platforms and game engines support WAV
- **No external dependencies**: Users don't need to install ffmpeg or other tools
- **Lossless quality**: No quality degradation during concatenation

For final deployment (especially web), you can convert the output WAV to OGG/MP3 using online tools.
