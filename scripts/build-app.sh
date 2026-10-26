#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$repo_dir/dist/MacTabber.app"
# Optional: VERSION=1.2.3 stamps CFBundleShortVersionString; BUILD_NUMBER sets CFBundleVersion.
# Optional: UNIVERSAL=1 builds for both arm64 and x86_64.
build_flags=(-c "$configuration")
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    build_flags+=(--arch arm64 --arch x86_64)
fi

cd "$repo_dir"
swift build "${build_flags[@]}"
binary_dir="$(swift build "${build_flags[@]}" --show-bin-path)"

rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/MacTabber" "$app_dir/Contents/MacOS/MacTabber"
cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$app_dir/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$app_dir/Contents/Info.plist"
fi
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
