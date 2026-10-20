#!/bin/bash
# Builds ScopeLink.app and the scopectl command-line tool as universal binaries
# (Intel macOS 10.14.4+ / Apple silicon macOS 11+). Run on a Mac with the Xcode command-line tools.
#
#   scripts/build.sh   -> dist/ScopeLink-<version>.zip
#
# Environment: APP_VERSION (default 0.1.0), BUILD_NUMBER, LIBUSB_VERSION (default 1.0.27)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build"
DIST="$ROOT/dist"
APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
LIBUSB_VERSION="${LIBUSB_VERSION:-1.0.27}"
ARCHS=(x86_64 arm64)

log() { printf '\n==> %s\n' "$*"; STEP="$*"; }
STEP="start"
BUILD_LOG="$(mktemp -t scopelink-build)"
exec > >(tee "$BUILD_LOG") 2>&1
report_failure() {
  local code=$? line=$1
  sleep 1
  local out; out="$(awk '/^==> /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$BUILD_LOG" | tail -n 60 | cut -c1-200)"
  printf 'Step: %s (line %s, exit %s)\n%s\n' "$STEP" "$line" "$code" "$out" > "$ROOT/diag.txt"
  local body; body="$(cat "$ROOT/diag.txt")"
  body="${body//'%'/'%25'}"; body="${body//$'\r'/}"; body="${body//$'\n'/'%0A'}"
  echo "::error title=Build failed during: ${STEP//[:,]/ }::$body"
  exit "$code"
}
trap 'report_failure $LINENO' ERR

min_for() { [ "$1" = x86_64 ] && echo 10.14 || echo 11.0; }
swift_min_for() { [ "$1" = x86_64 ] && echo 10.14.4 || echo 11.0; }
host_for() { [ "$1" = x86_64 ] && echo x86_64-apple-darwin || echo aarch64-apple-darwin; }

rm -rf "$WORK" "$DIST" "$ROOT/diag.txt"
mkdir -p "$WORK/src" "$DIST"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
echo "SDK: $SDK"
xcrun swiftc --version

log "Fetching libusb $LIBUSB_VERSION"
curl -fsSL "https://github.com/libusb/libusb/releases/download/v$LIBUSB_VERSION/libusb-$LIBUSB_VERSION.tar.bz2" \
  -o "$WORK/src/libusb.tar.bz2"

FRAMEWORKS=(-framework IOKit -framework CoreFoundation -framework Security -lobjc -lz)

for ARCH in "${ARCHS[@]}"; do
  MIN="$(min_for "$ARCH")"
  export MACOSX_DEPLOYMENT_TARGET="$MIN"
  CC_ARCH="clang -arch $ARCH -isysroot $SDK -mmacosx-version-min=$MIN"
  PREFIX="$WORK/$ARCH"

  log "libusb for $ARCH (min macOS $MIN)"
  mkdir -p "$WORK/libusb-$ARCH"
  tar -xjf "$WORK/src/libusb.tar.bz2" -C "$WORK/libusb-$ARCH" --strip-components=1
  ( cd "$WORK/libusb-$ARCH"
    CC="$CC_ARCH" ./configure --host="$(host_for "$ARCH")" --prefix="$PREFIX" \
      --disable-shared --enable-static --disable-dependency-tracking >/dev/null
    make -j"$(sysctl -n hw.ncpu)" >/dev/null
    make install >/dev/null )

  log "core + command-line tool for $ARCH"
  CFLAGS=(-O2 -Wall -Wextra -I"$PREFIX/include/libusb-1.0" -DSCOPELINK_VERSION="\"$APP_VERSION\"")
  mkdir -p "$WORK/obj-$ARCH"
  $CC_ARCH "${CFLAGS[@]}" -c "$ROOT/core/utd.c" -o "$WORK/obj-$ARCH/utd.o"
  $CC_ARCH "${CFLAGS[@]}" -c "$ROOT/core/png.c" -o "$WORK/obj-$ARCH/png.o"
  $CC_ARCH "${CFLAGS[@]}" "$ROOT/cli/main.c" "$WORK/obj-$ARCH/utd.o" "$WORK/obj-$ARCH/png.o" \
    "$PREFIX/lib/libusb-1.0.a" "${FRAMEWORKS[@]}" -o "$WORK/scopectl.$ARCH"

  log "tests for $ARCH"
  $CC_ARCH "${CFLAGS[@]}" "$ROOT/tests/test_core.c" "$WORK/obj-$ARCH/utd.o" "$WORK/obj-$ARCH/png.o" \
    "$PREFIX/lib/libusb-1.0.a" "${FRAMEWORKS[@]}" -o "$WORK/test.$ARCH"
  if [ "$ARCH" = "$(uname -m)" ]; then "$WORK/test.$ARCH" "$WORK/test.png" "$WORK/test.csv"
  else arch -"$ARCH" "$WORK/test.$ARCH" || echo "(could not run the $ARCH test on this machine)"; fi

  log "ScopeLink app for $ARCH"
  xcrun swiftc -O -sdk "$SDK" -target "$ARCH-apple-macos$(swift_min_for "$ARCH")" \
    -import-objc-header "$ROOT/app/Bridging.h" -Xcc -I"$PREFIX/include/libusb-1.0" \
    "$ROOT"/app/*.swift "$WORK/obj-$ARCH/utd.o" "$WORK/obj-$ARCH/png.o" "$PREFIX/lib/libusb-1.0.a" \
    -framework IOKit -framework CoreFoundation -framework Security -lz \
    -o "$WORK/ScopeLink.$ARCH" 2> "$WORK/swiftc-$ARCH.log" || {
      cat "$WORK/swiftc-$ARCH.log"
      { printf '### swiftc errors (%s)\n' "$ARCH"; grep -E 'error:' -A3 "$WORK/swiftc-$ARCH.log" | head -150; } > "$ROOT/diag-swift.txt"
      false
    }
  cat "$WORK/swiftc-$ARCH.log" >&2
done

log "Universal binaries"
# (the CLI is called scopectl: macOS file names are case-insensitive, so "scopelink" would overwrite "ScopeLink")
lipo -create "$WORK"/scopectl.x86_64 "$WORK"/scopectl.arm64 -output "$WORK/scopectl"
lipo -create "$WORK"/ScopeLink.x86_64 "$WORK"/ScopeLink.arm64 -output "$WORK/ScopeLink"
lipo -info "$WORK/scopectl" "$WORK/ScopeLink"
cmp -s "$WORK/scopectl" "$WORK/ScopeLink" && { echo "ERROR: scopectl and ScopeLink are the same file"; false; }
"$WORK/scopectl" --version

log "Checking deployment targets and libraries"
for B in "$WORK/scopectl" "$WORK/ScopeLink"; do
  otool -L "$B"
  if otool -L "$B" | grep -E '^[[:space:]]' | grep -v -E '^[[:space:]]+(/usr/lib/|/System/Library/|@rpath/libswift)'; then
    echo "ERROR: $B links to a library that is not on every Mac"; false
  fi
  for A in "${ARCHS[@]}"; do
    printf '%s %s: ' "$(basename "$B")" "$A"
    otool -arch "$A" -l "$B" | grep -A4 -E 'LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX' | grep -E 'minos|version' | head -2 | tr -s ' \n' ' '
    echo
  done
done

log "Assembling ScopeLink.app"
APP="$WORK/ScopeLink.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$WORK/ScopeLink" "$WORK/scopectl" "$APP/Contents/MacOS/"
sed -e "s/@VERSION@/$APP_VERSION/g" -e "s/@BUILD@/$BUILD_NUMBER/g" "$ROOT/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for S in 16 32 128 256 512; do
  sips -z $S $S "$ROOT/Resources/AppIcon-1024.png" --out "$ICONSET/icon_${S}x${S}.png" >/dev/null
  D=$((S * 2))
  sips -z $D $D "$ROOT/Resources/AppIcon-1024.png" --out "$ICONSET/icon_${S}x${S}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp "$WORK/libusb-x86_64/COPYING" "$APP/Contents/Resources/libusb-LICENSE.txt"

log "Signing (ad hoc)"
codesign --force --sign - "$APP/Contents/MacOS/scopectl"
codesign --force --sign - "$APP"
codesign --verify --verbose "$APP"

log "Packaging"
STAGE="$WORK/stage/ScopeLink-$APP_VERSION"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
cp "$WORK/scopectl" "$STAGE/scopectl"
codesign --force --sign - "$STAGE/scopectl"
cp "$ROOT/README.md" "$STAGE/README.md"
( cd "$WORK/stage" && ditto -c -k --sequesterRsrc --keepParent "ScopeLink-$APP_VERSION" "$DIST/ScopeLink-$APP_VERSION.zip" )
cp "$DIST/ScopeLink-$APP_VERSION.zip" "$DIST/ScopeLink-mac.zip"
ls -la "$DIST"
echo "Built ScopeLink $APP_VERSION"
