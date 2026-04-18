#!/bin/bash
set -e

echo "🔍 Step 1/3: Validating Package.swift..."
docker run --rm -v "$(pwd):/workspace" -w /workspace swift:6.0 \
  swift package dump-package > /dev/null
echo "✅ Package.swift is valid"

echo ""
echo "🔍 Step 2/3: Running SwiftLint..."
docker run --rm -v "$(pwd):/workspace" -w /workspace \
  --entrypoint /usr/local/bin/swiftlint norionomura/swiftlint:latest \
  lint --quiet --reporter summary
echo "✅ SwiftLint passed"

echo ""
echo "🔍 Step 3/3: Checking Swift syntax..."
SWIFT_FILES=$(find Sources -name '*.swift' -not -path '*.disabled' -not -path '*/.build/*')
TOTAL=$(echo "$SWIFT_FILES" | wc -l)
CURRENT=0
ERRORS=0

for file in $SWIFT_FILES; do
    CURRENT=$((CURRENT + 1))
    printf "\r[%d/%d] %s" "$CURRENT" "$TOTAL" "$file"
    
    if ! docker run --rm -v "$(pwd):/workspace" -w /workspace swift:6.0 \
        swiftc -parse "$file" 2>/tmp/swift-error-$$.txt >/dev/null; then
        echo ""
        echo "❌ Syntax error in $file:"
        cat /tmp/swift-error-$$.txt
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All $TOTAL files passed syntax check"
    echo ""
    echo "⚠️  Note: This does NOT verify:"
    echo "   - Type checking (requires macOS + SwiftUI)"
    echo "   - Imports and dependencies"
    echo "   - Full compilation"
    echo ""
    echo "👉 Push to GitHub to run full CI build on macOS"
    exit 0
else
    echo "❌ Found $ERRORS file(s) with syntax errors"
    exit 1
fi
