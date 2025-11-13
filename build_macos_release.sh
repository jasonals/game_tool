#!/bin/bash

# Build macOS Release Script for Game Tool
# This script builds a release version and creates a distributable zip file

set -e  # Exit on error

echo "🚀 Building macOS release..."
flutter build macos --release

echo ""
echo "📦 Creating zip archive..."
cd build/macos/Build/Products/Release
rm -f game_tool.app.zip  # Remove old zip if exists
zip -r game_tool.app.zip game_tool.app

echo ""
echo "✅ Build complete!"
echo ""
echo "📍 Location: build/macos/Build/Products/Release/game_tool.app.zip"
echo ""
echo "To share:"
echo "  1. Send the game_tool.app.zip file"
echo "  2. Recipient should unzip and move to Applications"
echo "  3. Right-click > Open (first time only)"

