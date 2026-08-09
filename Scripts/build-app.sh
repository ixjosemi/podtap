#!/usr/bin/env bash
#
# Builds PodTap.app from the SwiftPM executable.
#
# SwiftPM cannot produce application bundles, so it is assembled here: that is
# the difference between a loose binary and something you drag into
# /Applications and see in the menu bar.

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app="build/PodTap.app"
contents="$app/Contents"

# Xcode ships XCTest and the full SDKs; the Command Line Tools alone cannot
# compile SwiftUI.
if [[ -d /Applications/Xcode.app ]] && [[ "$(xcode-select -p)" != *Xcode* ]]; then
	export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> Building release binary"
swift build -c release --product PodTap

echo "==> Rendering app icon"
./Scripts/make-icon.sh >/dev/null

echo "==> Assembling $app"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"

cp ".build/release/PodTap" "$contents/MacOS/PodTap"
cp "build/AppIcon.icns" "$contents/Resources/AppIcon.icns"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
	Resources/Info.plist >"$contents/Info.plist"

# Ad-hoc signature. No substitute for notarisation, but without any signature
# macOS will not reliably grant Accessibility.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$app"

echo
echo "Done: $app"
echo "Install with:  cp -R $app /Applications/"
