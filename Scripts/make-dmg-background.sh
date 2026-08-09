#!/usr/bin/env bash
#
# Renders Design/dmg-background.svg into the committed background.tiff used by
# the installer window.
#
# Two quirks drive the shape of this script:
#
#   - qlmanage always emits a square image, fitting the source height and
#     cropping the width. The SVG is therefore nested inside a square canvas
#     and cropped back down with sips afterwards.
#   - Retina needs both scales in a single multi-representation TIFF, which is
#     what tiffutil produces.
#
# The result is committed, because qlmanage needs a window server session that
# CI runners cannot be relied on to have. Re-run this and commit when the SVG
# changes.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

width=660
height=420
staging="build/dmg-bg-staging"
output="Design/dmg-background.tiff"

rm -rf "$staging"
mkdir -p "$staging"

# Nest the landscape artwork inside a square canvas, vertically centred, so the
# square render can be cropped back to the real aspect ratio.
python3 - "$width" "$height" "$staging/square.svg" <<'PY'
import re, sys

width, height, destination = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
source = open("Design/dmg-background.svg").read()

inner = re.sub(r"^<\?xml[^>]*\?>\s*", "", source).strip()
inner = inner.replace(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 660 420" width="660" height="420"',
    f'<svg x="0" y="{(width - height) // 2}" viewBox="0 0 660 420" '
    f'width="{width}" height="{height}"',
    1,
)

open(destination, "w").write(
    f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {width}" '
    f'width="{width}" height="{width}">{inner}</svg>'
)
PY

render() {
	local scale="$1" out="$2"
	local square=$((width * scale))
	local crop_height=$((height * scale))

	qlmanage -t -s "$square" -o "$staging" "$staging/square.svg" >/dev/null 2>&1
	local rendered="$staging/square.svg.png"
	[[ -f "$rendered" ]] || { echo "error: qlmanage produced nothing" >&2; exit 1; }

	# sips takes height then width, and crops from the centre.
	sips -c "$crop_height" "$square" "$rendered" --out "$out" >/dev/null
	rm -f "$rendered"
}

echo "==> Rendering 1x and 2x"
render 1 "$staging/bg.png"
render 2 "$staging/bg@2x.png"

echo "==> Packing $output"
tiffutil -cathidpicheck "$staging/bg.png" "$staging/bg@2x.png" -out "$output" >/dev/null

rm -rf "$staging"
echo "Done: $output (commit it)"
