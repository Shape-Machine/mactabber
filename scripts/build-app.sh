#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$repo_dir/dist/MacTabber.app"
# Optional: VERSION=1.2.3 stamps CFBundleShortVersionString; BUILD_NUMBER sets CFBundleVersion.
# Optional: UNIVERSAL=1 builds for both arm64 and x86_64.
cd "$repo_dir"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    # Build each arch separately and merge; multi-arch `swift build` goes through
    # XCBuild, which rejects swiftLanguageMode on some Xcode versions.
    slices=()
    for arch in arm64 x86_64; do
        swift build -c "$configuration" --arch "$arch"
        slices+=("$(swift build -c "$configuration" --arch "$arch" --show-bin-path)/MacTabber")
    done
    lipo -create "${slices[@]}" -output "$app_dir/Contents/MacOS/MacTabber"
else
    swift build -c "$configuration"
    cp "$(swift build -c "$configuration" --show-bin-path)/MacTabber" "$app_dir/Contents/MacOS/MacTabber"
fi

cp "$repo_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$app_dir/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
    plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$app_dir/Contents/Info.plist"
fi
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
