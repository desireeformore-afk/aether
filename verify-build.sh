#!/bin/bash
set -e

echo "🔍 Verifying Swift build..."

# Run Swift build in Docker container
docker run --rm \
  -v "$(pwd):/workspace" \
  -w /workspace \
  swift:6.0 \
  swift build --build-tests

echo "✅ Build verification passed!"
