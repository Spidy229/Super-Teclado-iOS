#!/bin/bash
set -euo pipefail

rm -rf build Payload Super-Teclado-unsigned.ipa \
  Super-Teclado-unsigned.ipa.sha256 Super-Teclado-build-info.json

xcodegen generate --spec project.yml

xcodebuild \
  -project SuperTeclado.xcodeproj \
  -scheme SuperTeclado \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  clean build

APP_PATH="build/Build/Products/Release-iphoneos/SuperTeclado.app"
test -d "$APP_PATH"

# Sin el catálogo compilado iOS muestra el icono genérico de cuadrícula.
if [ ! -f "$APP_PATH/Assets.car" ] || ! /usr/libexec/PlistBuddy -c 'Print :CFBundleIcons:CFBundlePrimaryIcon' "$APP_PATH/Info.plist" >/dev/null 2>&1; then
  echo "error: la app no incluye el icono (falta Assets.car o CFBundleIcons)" >&2
  exit 1
fi

KEYBOARD_PATH="$APP_PATH/PlugIns/SuperTecladoKeyboard.appex"
test -d "$KEYBOARD_PATH"

codesign --force --sign - \
  --entitlements SuperTecladoKeyboard/SuperTecladoKeyboard.entitlements \
  "$KEYBOARD_PATH"

SHARE_PATH="$APP_PATH/PlugIns/SuperTecladoShare.appex"
test -d "$SHARE_PATH"

codesign --force --sign - \
  --entitlements SuperTecladoShare/SuperTecladoShare.entitlements \
  "$SHARE_PATH"

WIDGET_PATH="$APP_PATH/PlugIns/SuperTecladoWidget.appex"
test -d "$WIDGET_PATH"

codesign --force --sign - \
  --entitlements SuperTecladoWidget/SuperTecladoWidget.entitlements \
  "$WIDGET_PATH"

codesign --force --sign - \
  --entitlements SuperTecladoApp/SuperTeclado.entitlements \
  "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"

# La versión del release sale de los cuatro bundles realmente compilados.
python3 - "$APP_PATH" <<'PY'
import json
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
with (app / "Info.plist").open("rb") as source:
    metadata = plistlib.load(source)
extensions = []
for name in ("SuperTecladoKeyboard", "SuperTecladoShare", "SuperTecladoWidget"):
    with (app / "PlugIns" / f"{name}.appex" / "Info.plist").open("rb") as source:
        extension = plistlib.load(source)
    for key in ("CFBundleShortVersionString", "CFBundleVersion"):
        if extension[key] != metadata[key]:
            raise SystemExit(f"Version mismatch: {name} {key}")
    extensions.append({
        "bundle_identifier": extension["CFBundleIdentifier"],
        "version": extension["CFBundleShortVersionString"],
        "build": extension["CFBundleVersion"],
    })
with open("Super-Teclado-build-info.json", "w") as target:
    json.dump({
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "version": metadata["CFBundleShortVersionString"],
        "build": metadata["CFBundleVersion"],
        "bundle_identifier": metadata["CFBundleIdentifier"],
        "extensions": extensions,
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "apple_signed": False,
    }, target, indent=2)
    target.write("\n")
PY

mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry Super-Teclado-unsigned.ipa Payload

unzip -t Super-Teclado-unsigned.ipa
shasum -a 256 Super-Teclado-unsigned.ipa > Super-Teclado-unsigned.ipa.sha256
ls -lh Super-Teclado-unsigned.ipa
