#!/bin/bash
# Run this on your Mac in the aether project directory
set -e

echo "📦 Installing xcodegen..."
if ! command -v xcodegen &> /dev/null; then
  brew install xcodegen
fi

echo "🗑️  Removing old broken xcodeproj..."
rm -rf Aether.xcodeproj

echo "🔨 Generating fresh Xcode project..."
xcodegen generate

echo "✅ Done! Now open Aether.xcodeproj in Xcode."
echo "   Select scheme: AetherApp"
echo "   Click Run"
