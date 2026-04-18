#!/bin/bash
set -e

echo "🔍 Verifying Swift syntax..."

# Find all Swift files (excluding disabled)
SWIFT_FILES=$(find Sources -name '*.swift' -not -path '*.disabled')
TOTAL=$(echo "$SWIFT_FILES" | wc -l)
CURRENT=0
ERRORS=0

for file in $SWIFT_FILES; do
    CURRENT=$((CURRENT + 1))
    printf "\r[%d/%d] Checking %s..." "$CURRENT" "$TOTAL" "$file"
    
    if ! docker run --rm -v "$(pwd):/workspace" -w /workspace swift:6.0 \
        swiftc -parse "$file" 2>/tmp/swift-error-$$.txt; then
        echo ""
        echo "❌ Error in $file:"
        cat /tmp/swift-error-$$.txt
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All $TOTAL files passed syntax check!"
    exit 0
else
    echo "❌ Found $ERRORS file(s) with syntax errors"
    exit 1
fi
