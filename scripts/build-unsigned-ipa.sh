#!/bin/bash
set -euo pipefail

rm -rf build Payload Super-Teclado-unsigned.ipa

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

mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry Super-Teclado-unsigned.ipa Payload

unzip -t Super-Teclado-unsigned.ipa
ls -lh Super-Teclado-unsigned.ipa
