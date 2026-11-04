#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--universal" ) ]]; then
    printf 'Usage: %s [--universal]\n' "$0" >&2
    exit 2
fi

mkdir -p .build/{clang,swiftpm-cache,swiftpm-config,swiftpm-security} dist
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang"
build_options=(
    -c release
    --cache-path .build/swiftpm-cache
    --config-path .build/swiftpm-config
    --security-path .build/swiftpm-security
)
if [[ "${BOOKBAR_SWIFTPM_SANDBOX:-1}" == 0 ]]; then
    build_options+=(--disable-sandbox)
fi

staging="$(mktemp -d "$PWD/.build/bundle.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/BookBar.app"
executable="$bundle/Contents/MacOS/BookBar"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"

if [[ "${1:-}" == "--universal" ]]; then
    binaries=()
    for arch in arm64 x86_64; do
        triple="$arch-apple-macosx13.0"
        swift build "${build_options[@]}" --triple "$triple"
        binary_dir="$(swift build "${build_options[@]}" --triple "$triple" --show-bin-path)"
        binaries+=("$binary_dir/BookBar")
    done
    xcrun lipo -create "${binaries[@]}" -output "$executable"
else
    swift build "${build_options[@]}"
    binary_dir="$(swift build "${build_options[@]}" --show-bin-path)"
    cp "$binary_dir/BookBar" "$executable"
fi

cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp LICENSE "$bundle/Contents/Resources/LICENSE"
swift scripts/draw-icon.swift "$staging/BookBar.png"
sips -s format icns "$staging/BookBar.png" --out "$bundle/Contents/Resources/BookBar.icns" >/dev/null
codesign --force --sign - "$bundle"
codesign --verify --strict --all-architectures "$bundle"

rm -rf "$PWD/dist/BookBar.app"
mv "$bundle" "$PWD/dist/BookBar.app"
printf '%s\n' "$PWD/dist/BookBar.app"
