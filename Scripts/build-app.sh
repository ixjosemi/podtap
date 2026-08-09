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
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
	# Release builds ship universal: CI runners are Apple Silicon, and an
	# arm64-only binary would simply not launch on an Intel Mac.
	swift build -c release --product PodTap --arch arm64 --arch x86_64
	binary=".build/apple/Products/Release/PodTap"
else
	swift build -c release --product PodTap
	binary=".build/release/PodTap"
fi

if [[ ! -f "$binary" ]]; then
	echo "error: expected the built binary at $binary but it is not there" >&2
	exit 1
fi

# The icon is a committed artefact: rendering it needs qlmanage, which needs a
# window server session that CI runners cannot be relied on to have. Only
# regenerate when it is genuinely missing.
if [[ ! -f Resources/AppIcon.icns ]]; then
	echo "==> Icon missing, rendering it"
	./Scripts/make-icon.sh >/dev/null
fi

echo "==> Assembling $app"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"

cp "$binary" "$contents/MacOS/PodTap"
cp "Resources/AppIcon.icns" "$contents/Resources/AppIcon.icns"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
	Resources/Info.plist >"$contents/Info.plist"

# Ad-hoc signature. No substitute for notarisation, but without any signature
# macOS will not reliably grant Accessibility.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$app"

echo
echo "Done: $app"
echo "Install with:  cp -R $app /Applications/"
