#!/usr/bin/env bash
#
# Construye PodTap.app a partir del ejecutable de SwiftPM.
#
# SwiftPM no sabe producir bundles de aplicación, así que lo ensamblamos aquí:
# es la diferencia entre un binario suelto y algo que se arrastra a
# /Applications y aparece en la barra de menús.

set -euo pipefail

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

app="build/PodTap.app"
contents="$app/Contents"

# Xcode trae XCTest y los SDKs completos; las Command Line Tools por sí solas
# no bastan para compilar SwiftUI.
if [[ -d /Applications/Xcode.app ]] && [[ "$(xcode-select -p)" != *Xcode* ]]; then
	export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> Compilando en release"
swift build -c release --product PodTap

echo "==> Ensamblando $app"
rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"

cp ".build/release/PodTap" "$contents/MacOS/PodTap"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" \
	Resources/Info.plist >"$contents/Info.plist"

# Firma ad-hoc. No sustituye a la notarización, pero sin ninguna firma macOS
# rechaza conceder permisos de Accesibilidad de forma fiable.
echo "==> Firmando (ad-hoc)"
codesign --force --deep --sign - "$app"

echo
echo "Listo: $app"
echo "Instalar con:  cp -R $app /Applications/"
