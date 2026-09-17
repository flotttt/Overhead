#!/bin/bash
# Builds build/SonyNotch.app with the Command Line Tools only (no Xcode needed).
#   CONFIG=debug|release (default: debug)
#   ARCHS="arm64 x86_64"  (default: this Mac's architecture; several = universal binary via lipo)
#   DEBUG_PROTOCOL=1      (hex-dumps every frame exchanged with the headphones to stderr)
#   SIGN_IDENTITY=name    (default: "SonyNotch Code Signing" when that certificate is in a keychain, else ad-hoc)
#   SIGN_KEYCHAIN=path    (keychain holding SIGN_IDENTITY, default: the search list)
#
# Every release is signed with the same certificate, so macOS keeps the Bluetooth and Spotify permissions across
# updates. An ad-hoc signature is identified by the binary's hash, which changes with every build.
set -euo pipefail
shopt -s nullglob

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CORE=$ROOT/Client
MAC=$CORE/macos
OUT=$ROOT/build
APP=$OUT/SonyNotch.app
SDK=$(xcrun --show-sdk-path)
CONFIG=${CONFIG:-debug}
ARCHS=${ARCHS:-$(uname -m)}
MIN_MACOS=13.0

if [ "$CONFIG" = release ]; then SWIFT_OPT="-O"; CXX_OPT="-O2"; else SWIFT_OPT="-Onone -g"; CXX_OPT="-O0 -g"; fi
SWIFT_DEFINES=""; CXX_DEFINES=""
if [ "${DEBUG_PROTOCOL:-0}" = 1 ]; then SWIFT_DEFINES="-D DEBUG_PROTOCOL"; CXX_DEFINES="-DSHC_DEBUG_PROTOCOL"; fi

SWIFT_SOURCES=("$MAC"/*.swift "$MAC"/MenuRows/*.swift "$MAC"/Notch/*.swift "$MAC"/Updates/*.swift "$MAC"/Music/*.swift)
CXX_SOURCES=("$CORE"/*.cpp)
OBJCXX_SOURCES=("$MAC"/*.mm)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BINARIES=""

for ARCH in $ARCHS; do
    OBJ=$OUT/obj/$CONFIG-$ARCH
    rm -rf "$OBJ"; mkdir -p "$OBJ"
    TARGET=$ARCH-apple-macos$MIN_MACOS
    CXXFLAGS="-target $TARGET -isysroot $SDK -std=c++17 $CXX_OPT $CXX_DEFINES -I $CORE -I $MAC"

    echo "== [$ARCH] Swift"
    swiftc -target "$TARGET" -sdk "$SDK" -swift-version 5 $SWIFT_OPT $SWIFT_DEFINES -wmo -parse-as-library \
        -module-name SonyNotch \
        -import-objc-header "$MAC/SonyHeadphonesClient-Bridging-Header.h" -I "$MAC" -I "$CORE" \
        -c "${SWIFT_SOURCES[@]}" -o "$OBJ/swift.o"

    echo "== [$ARCH] C++"
    for f in "${CXX_SOURCES[@]}"; do clang++ $CXXFLAGS -c "$f" -o "$OBJ/$(basename "$f" .cpp).o"; done

    echo "== [$ARCH] Obj-C++"
    for f in "${OBJCXX_SOURCES[@]}"; do
        clang++ $CXXFLAGS -fobjc-arc -fmodules -fcxx-modules -c "$f" -o "$OBJ/$(basename "$f" .mm).o"
    done

    echo "== [$ARCH] Link"
    swiftc -target "$TARGET" -sdk "$SDK" "$OBJ"/*.o -o "$OBJ/SonyNotch" -lc++ \
        -framework AppKit -framework SwiftUI -framework Combine -framework IOBluetooth \
        -framework IOBluetoothUI -framework ServiceManagement
    BINARIES="$BINARIES $OBJ/SonyNotch"
done

lipo -create $BINARIES -output "$APP/Contents/MacOS/SonyNotch"

echo "== Resources"
cp "$MAC/info.plist" "$APP/Contents/Info.plist"
cp -R "$MAC"/*.lproj "$APP/Contents/Resources/"
iconutil -c icns "$MAC/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

DEFAULT_IDENTITY="SonyNotch Code Signing"
if [ -z "${SIGN_IDENTITY:-}" ] && security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} 2>/dev/null \
        | grep -q "\"$DEFAULT_IDENTITY\""; then
    SIGN_IDENTITY=$DEFAULT_IDENTITY
fi
SIGN_IDENTITY=${SIGN_IDENTITY:--}
echo "== Sign ($([ "$SIGN_IDENTITY" = - ] && echo ad-hoc || echo "$SIGN_IDENTITY"))"
codesign --force --sign "$SIGN_IDENTITY" ${SIGN_KEYCHAIN:+--keychain "$SIGN_KEYCHAIN"} \
    --entitlements "$MAC/SonyHeadphonesClient.entitlements" "$APP"
echo "OK -> $APP"
