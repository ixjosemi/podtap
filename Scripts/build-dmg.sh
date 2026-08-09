#!/usr/bin/env bash
#
# Packages PodTap.app into a drag-to-install disk image.
#
# The DMG only installs. Permissions and the key mapping are handled by the
# setup window that opens the first time PodTap runs, which is the only moment
# the app can actually check whether macOS granted anything.

set -euo pipefail

VERSION="${VERSION:-0.1.0}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app="build/PodTap.app"
staging="build/dmg-staging"
output="build/PodTap-$VERSION.dmg"

if [[ ! -d "$app" ]]; then
	echo "==> $app not found, building it first"
	VERSION="$VERSION" ./Scripts/build-app.sh
fi

echo "==> Staging disk image contents"
rm -rf "$staging" "$output"
mkdir -p "$staging"

cp -R "$app" "$staging/"
# The symlink is what makes the window a drag-and-drop target.
ln -s /Applications "$staging/Applications"

echo "==> Creating $output"
hdiutil create \
	-volname "PodTap $VERSION" \
	-srcfolder "$staging" \
	-ov \
	-format UDZO \
	"$output" >/dev/null

rm -rf "$staging"

echo
echo "Done: $output"
echo
echo "Note: the image is not notarised, so the first launch needs"
echo "right-click > Open. PodTap then walks the user through permissions."
