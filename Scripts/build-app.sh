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

# Signing identity decides whether permissions survive a rebuild.
#
# An ad-hoc signature produces a designated requirement pinned to the binary's
# cdhash, which changes every build — so macOS treats each rebuild as a
# different app and silently drops its Accessibility and Input Monitoring
# grants. Signing with a real certificate pins the requirement to the bundle
# identifier and the certificate instead, and the grants persist.
#
# Set PODTAP_SIGNING_IDENTITY to choose explicitly. Otherwise a single
# available identity is used automatically; CI has none and falls back to
# ad-hoc, which is correct there.
identity="${PODTAP_SIGNING_IDENTITY:-}"

if [[ -z "$identity" ]]; then
	available="$(security find-identity -v -p codesigning 2>/dev/null |
		sed -n 's/^ *[0-9]*) [0-9A-F]* "\(.*\)"$/\1/p')"
	if [[ "$(printf '%s' "$available" | grep -c .)" == "1" ]]; then
		identity="$available"
	fi
fi

sign_ad_hoc() {
	echo "==> Signing (ad-hoc — permissions reset on every rebuild)"
	codesign --force --sign - "$app"
}

if [[ -n "$identity" ]]; then
	echo "==> Signing as: $identity"
	codesign --force --sign "$identity" "$app"

	# A revoked certificate is far worse than no certificate: macOS treats
	# anything signed with one as malware, and XProtect deletes it outright.
	# Revocation is checked online at assessment time, so a revoked identity
	# still shows up as "valid" in `security find-identity` — the keychain
	# genuinely does not know. This is the only reliable check.
	assessment="$(spctl --assess --type execute -vvv "$app" 2>&1 || true)"
	if grep -q "CERT_REVOKED" <<<"$assessment"; then
		echo "    warning: that certificate is REVOKED. Falling back to ad-hoc." >&2
		echo "    Create a fresh one in Xcode > Settings > Accounts >" >&2
		echo "    Manage Certificates, or unset PODTAP_SIGNING_IDENTITY." >&2
		sign_ad_hoc
	fi
else
	sign_ad_hoc
fi

echo
echo "Done: $app"
echo "Install with:  cp -R $app /Applications/"
