#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

VLCKIT_DIR=".vlckit"
VLCKIT_FRAMEWORK="${VLCKIT_DIR}/VLCKit.xcframework"
DEFAULT_VLCKIT_URL="https://download.videolan.org/pub/cocoapods/unstable/VLCKit-4.0.0a19-d7597c1706-85a537d69.tar.xz"
VLCKIT_URL="${VLCKIT_URL:-$DEFAULT_VLCKIT_URL}"

if [[ -d "$VLCKIT_FRAMEWORK" ]]; then
    echo "VLCKit already installed at ${VLCKIT_FRAMEWORK}"
    exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

ARCHIVE="${TMP_DIR}/vlckit.tar.xz"
EXTRACT_DIR="${TMP_DIR}/extracted"
mkdir -p "$EXTRACT_DIR"

echo "Downloading VLCKit from ${VLCKIT_URL}"
curl -fL --retry 3 -o "$ARCHIVE" "$VLCKIT_URL"

echo "Extracting VLCKit archive"
tar -xf "$ARCHIVE" -C "$EXTRACT_DIR"

FOUND_FRAMEWORK="$(find "$EXTRACT_DIR" -type d -name "VLCKit.xcframework" -print -quit)"
if [[ -z "$FOUND_FRAMEWORK" ]]; then
    echo "error: VLCKit.xcframework not found in downloaded archive." >&2
    echo "VLCKit artifacts found:" >&2
    FOUND_ARTIFACTS="$(find "$EXTRACT_DIR" -name "VLCKit*" -print | sort)"
    if [[ -n "$FOUND_ARTIFACTS" ]]; then
        printf '%s\n' "$FOUND_ARTIFACTS" >&2
    else
        echo "(none)" >&2
    fi
    exit 1
fi

mkdir -p "$VLCKIT_DIR"
rm -rf "$VLCKIT_FRAMEWORK"
cp -R "$FOUND_FRAMEWORK" "$VLCKIT_FRAMEWORK"

echo "Installed VLCKit to ${VLCKIT_FRAMEWORK}"
