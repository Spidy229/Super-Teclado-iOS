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

KEYBOARD_PATH="$APP_PATH/PlugIns/SuperTecladoKeyboard.appex"
test -d "$KEYBOARD_PATH"

codesign --force --sign - \
  --entitlements SuperTecladoKeyboard/SuperTecladoKeyboard.entitlements \
  "$KEYBOARD_PATH"

codesign --force --sign - \
  --entitlements SuperTecladoApp/SuperTeclado.entitlements \
  "$APP_PATH"

codesign --verify --deep --strict "$APP_PATH"

mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry Super-Teclado-unsigned.ipa Payload

unzip -t Super-Teclado-unsigned.ipa
shasum -a 256 Super-Teclado-unsigned.ipa > Super-Teclado-unsigned.ipa.sha256
python3 - "$APP_PATH/Info.plist" <<'PY'
import json
import plistlib
import subprocess
import sys

with open(sys.argv[1], "rb") as source:
    metadata = plistlib.load(source)
with open("Super-Teclado-build-info.json", "w") as target:
    json.dump({
        "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
        "version": metadata["CFBundleShortVersionString"],
        "build": metadata["CFBundleVersion"],
        "bundle_identifier": metadata["CFBundleIdentifier"],
        "xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
        "apple_signed": False,
    }, target, indent=2)
    target.write("\n")
PY
ls -lh Super-Teclado-unsigned.ipa
