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

mkdir -p Payload
cp -R "$APP_PATH" Payload/
zip -qry Super-Teclado-unsigned.ipa Payload

unzip -t Super-Teclado-unsigned.ipa
ls -lh Super-Teclado-unsigned.ipa
