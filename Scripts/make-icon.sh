#!/usr/bin/env bash
#
# Renders Design/icon.svg into Resources/AppIcon.icns.
#
# There is no SVG rasteriser in a stock macOS install, but QuickLook renders
# SVG through WebKit, which is enough to get a clean 1024px master. Everything
# else is sips downscaling and iconutil packing.
#
# The resulting .icns is committed to the repository on purpose: qlmanage needs
# a window server session, which CI runners cannot be relied on to provide.
# Run this by hand whenever the SVG changes, and commit the result.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

source_svg="Design/icon.svg"
staging="build/icon-staging"
iconset="build/AppIcon.iconset"
output="Resources/AppIcon.icns"

rm -rf "$staging" "$iconset"
mkdir -p "$staging" "$iconset"

echo "==> Rasterising $source_svg at 1024px"
qlmanage -t -s 1024 -o "$staging" "$source_svg" >/dev/null 2>&1

master="$staging/$(basename "$source_svg").png"
if [[ ! -f "$master" ]]; then
	echo "error: QuickLook produced no output. Is $source_svg valid SVG?" >&2
	exit 1
fi

# Every size macOS asks for, as base size plus its @2x retina variant.
for size in 16 32 128 256 512; do
	sips -z "$size" "$size" "$master" \
		--out "$iconset/icon_${size}x${size}.png" >/dev/null
	sips -z "$((size * 2))" "$((size * 2))" "$master" \
		--out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

echo "==> Packing $output"
iconutil --convert icns --output "$output" "$iconset"
rm -rf "$staging" "$iconset"

echo "Done: $output (commit it)"
