# Game Tool - Texture & Audio Packer

A Flutter-based desktop application for game development that provides two essential tools:

## Features

### 1. Texture Atlas Packer
Pack multiple sprite images into optimized texture atlases with JSON metadata for Phaser or other game engines.

**Features:**
- Multiple packing formats (Array, Hash, Multi-page)
- Power-of-two dimension support
- Sprite rotation for better packing
- Trim transparent pixels
- Edge extrusion
- Interactive preview
- Load/Save `.tps` project files

### 2. Audio Sprite Packer
Combine multiple audio files into a single audio file with timing metadata for efficient audio loading in games.

**Features:**
- **Zero Dependencies**: Pure Dart implementation - no ffmpeg required!
- WAV format support
- Adjustable sample rate
- Automatic format conversion (mono/stereo, resampling)
- Phaser-compatible JSON output
- Selective file inclusion

See [AUDIO_PACKER.md](AUDIO_PACKER.md) for detailed audio packer documentation.

## Requirements

- **Flutter SDK** 3.9.2 or higher
- **No external dependencies** for audio packing!

### Audio Files

The audio packer works with **WAV files only**. If you have audio in other formats, convert them to WAV first using:
- Online converters (CloudConvert, Online-Convert, etc.)
- macOS: `afconvert input.mp3 output.wav -d LEI16@44100`
- Audacity (free audio editor)

This design choice eliminates the need to install ffmpeg or other tools, reducing friction for users.

## Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the app:
   ```bash
   flutter run
   ```

## Usage

Launch the application and use the navigation rail on the left to switch between:
- **Texture Atlas** - Pack sprite images
- **Audio Sprite** - Pack audio files (WAV format)

Both tools have similar workflows:
1. Select source folder
2. Select output folder
3. Configure settings
4. Select which files to include
5. Pack

## Building

Build for your platform:

```bash
# macOS
flutter build macos

# Windows
flutter build windows

# Linux
flutter build linux
```

## Why WAV for Audio?

The audio packer uses WAV format exclusively because:
- **No external dependencies** - Pure Dart implementation
- **Universal compatibility** - Works everywhere
- **Simple format** - Easy to parse and manipulate
- **Lossless quality** - No degradation during concatenation
- **Zero installation friction** - Users don't need ffmpeg

For web deployment, you can convert the final WAV output to OGG/MP3 using online tools if needed.

## License

This project is available for use in game development projects.
