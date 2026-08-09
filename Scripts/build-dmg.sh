#!/usr/bin/env bash
#
# Packages PodTap.app into a drag-to-install disk image.
#
# The window layout comes from a committed .DS_Store rather than being built
# here, because styling a disk image means driving Finder over AppleScript and
# CI has no window server. See Scripts/make-dmg-layout.sh.
#
# The disk image only installs. Permissions and the key mapping are handled by
# the setup window that opens the first time PodTap runs, which is the only
# moment the app can actually check what macOS granted.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# Same single source of truth as build-app.sh, so the disk image cannot be
# named after a different version than the bundle inside it.
VERSION="$(tr -d '[:space:]' <VERSION)"

# Constant on purpose: .DS_Store records the background image by path inside
# the volume, so a versioned volume name would break the layout every release.
volume="PodTap"

app="build/PodTap.app"
staging="build/dmg-staging"
output="build/PodTap-$VERSION.dmg"

if [[ ! -d "$app" ]]; then
	echo "==> $app not found, building it first"
	./Scripts/build-app.sh
fi

echo "==> Staging disk image contents"
rm -rf "$staging" "$output"
mkdir -p "$staging/.background"

cp -R "$app" "$staging/"
# The symlink is what makes the window a drag-and-drop target.
ln -s /Applications "$staging/Applications"
cp Design/dmg-background.tiff "$staging/.background/background.tiff"

# Icon positions, window size, background and view mode all live in here.
cp Design/dmg-DS_Store "$staging/.DS_Store"

echo "==> Creating $output"
hdiutil create \
	-volname "$volume" \
	-srcfolder "$staging" \
	-ov \
	-format UDZO \
	"$output" >/dev/null

rm -rf "$staging"

echo
echo "Done: $output"
echo
echo "Note: the image is not notarised. macOS quarantines it on download, and"
echo "the installer window tells the user how to clear that."
