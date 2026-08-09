#!/usr/bin/env bash
#
# Produces Design/dmg-DS_Store: the Finder window layout for the installer.
#
# Styling a disk image means driving Finder over AppleScript, which needs a
# window server session and Automation permission. CI has neither. So the
# layout is baked once, here, on a real desktop, and the resulting .DS_Store is
# committed and simply copied in by build-dmg.sh.
#
# Re-run this only when the window design changes, and commit the result.
#
# The volume name must stay constant: .DS_Store records the background image by
# path inside the volume, so a versioned volume name would break the layout on
# every release.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

volume="PodTap"
mount_point="/Volumes/$volume"
staging="build/layout-staging"
scratch="build/layout-rw.dmg"
output="Design/dmg-DS_Store"

window_width=660
window_height=420
icon_size=128

# Finder's `bounds` includes the title bar, so asking for exactly the
# background height crops the bottom of the image. Pad by the title bar.
title_bar=28
frame_height=$((window_height + title_bar))

if [[ ! -d build/PodTap.app ]]; then
	echo "==> build/PodTap.app missing, building it"
	./Scripts/build-app.sh
fi

if [[ ! -f Design/dmg-background.tiff ]]; then
	echo "==> Background missing, rendering it"
	./Scripts/make-dmg-background.sh
fi

echo "==> Staging"
hdiutil detach "$mount_point" -quiet 2>/dev/null || true
rm -rf "$staging" "$scratch"
mkdir -p "$staging/.background"

cp -R build/PodTap.app "$staging/"
ln -s /Applications "$staging/Applications"
cp Design/dmg-background.tiff "$staging/.background/background.tiff"

echo "==> Creating writable image"
hdiutil create -srcfolder "$staging" -volname "$volume" -fs HFS+ \
	-format UDRW -size 300m -ov "$scratch" >/dev/null

hdiutil attach "$scratch" -mountpoint "$mount_point" -nobrowse -quiet

echo "==> Arranging the window in Finder"
osascript <<APPLESCRIPT
tell application "Finder"
	tell disk "$volume"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {200, 120, $((200 + window_width)), $((120 + frame_height))}

		set viewOptions to the icon view options of container window
		set arrangement of viewOptions to not arranged
		set icon size of viewOptions to $icon_size
		set text size of viewOptions to 12
		set background picture of viewOptions to file ".background:background.tiff"

		set position of item "PodTap.app" of container window to {170, 200}
		set position of item "Applications" of container window to {490, 200}

		update without registering applications
		delay 2
		close
	end tell
end tell
APPLESCRIPT

# Finder writes .DS_Store lazily. Detaching and reattaching guarantees the file
# on disk is the final one rather than a half-written buffer.
sync
hdiutil detach "$mount_point" -quiet
hdiutil attach "$scratch" -mountpoint "$mount_point" -nobrowse -quiet

if [[ ! -f "$mount_point/.DS_Store" ]]; then
	hdiutil detach "$mount_point" -quiet || true
	echo "error: Finder wrote no .DS_Store. Grant this terminal Automation" >&2
	echo "       access to Finder in Privacy & Security, then retry." >&2
	exit 1
fi

cp "$mount_point/.DS_Store" "$output"
hdiutil detach "$mount_point" -quiet
rm -rf "$staging" "$scratch"

echo "Done: $output ($(wc -c <"$output" | tr -d ' ') bytes) — commit it"
