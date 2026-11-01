#!/bin/zsh
# Rebuilds Jpegli.xcframework and the vendored headers from a pinned google/jpegli commit.
# Usage: Packages/Jpegli/build-jpegli.sh [path to an existing jpegli checkout]
set -euo pipefail

JPEGLI_COMMIT=031a0077f5799a6041004267fc12b956c1f52a20
PACKAGE_DIR=${0:A:h}
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

if [[ $# -ge 1 ]]; then
    SOURCE_DIR=${1:A}
else
    SOURCE_DIR=$WORK_DIR/jpegli
    git clone --quiet https://github.com/google/jpegli.git "$SOURCE_DIR"
fi
git -C "$SOURCE_DIR" checkout --quiet $JPEGLI_COMMIT
# Only highway and libjpeg-turbo (headers) are compiled in; CMake insists on a CMS at configure time
git -C "$SOURCE_DIR" submodule update --init --depth 1 third_party/highway third_party/libjpeg-turbo third_party/skcms

BUILD_DIR=$WORK_DIR/build
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
    -DBUILD_SHARED_LIBS=OFF -DBUILD_TESTING=OFF \
    -DJPEGLI_ENABLE_TOOLS=OFF -DJPEGLI_ENABLE_DEVTOOLS=OFF -DJPEGLI_ENABLE_JPEGLI_LIBJPEG=OFF \
    -DJPEGLI_ENABLE_BENCHMARK=OFF -DJPEGLI_ENABLE_SJPEG=OFF -DJPEGLI_ENABLE_OPENEXR=OFF \
    -DJPEGLI_ENABLE_JNI=OFF -DJPEGLI_ENABLE_DOXYGEN=OFF -DJPEGLI_ENABLE_MANPAGES=OFF \
    -DJPEGLI_ENABLE_FUZZERS=OFF -DJPEGLI_ENABLE_TCMALLOC=OFF -DJPEGLI_ENABLE_SKCMS=ON \
    -DHWY_ENABLE_TESTS=OFF -DHWY_ENABLE_EXAMPLES=OFF -DHWY_ENABLE_CONTRIB=OFF > /dev/null
ninja -C "$BUILD_DIR" jpegli-static hwy > /dev/null

# One static library holding jpegli and highway
libtool -static -o "$WORK_DIR/libjpegli.a" \
    "$BUILD_DIR/lib/libjpegli-static.a" "$BUILD_DIR/third_party/highway/libhwy.a" 2> /dev/null

rm -rf "$PACKAGE_DIR/Jpegli.xcframework"
xcodebuild -create-xcframework -library "$WORK_DIR/libjpegli.a" \
    -output "$PACKAGE_DIR/Jpegli.xcframework" > /dev/null

VENDOR_DIR=$PACKAGE_DIR/Sources/CJpegli/vendor
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR/lib/jpegli" "$VENDOR_DIR/lib/base"
cp "$SOURCE_DIR"/lib/jpegli/{encode,common,types}.h "$VENDOR_DIR/lib/jpegli/"
cp "$SOURCE_DIR/lib/base/include_jpeglib.h" "$VENDOR_DIR/lib/base/"
cp "$BUILD_DIR"/lib/include/jpegli/{jpeglib,jconfig,jmorecfg}.h "$VENDOR_DIR/"
cp "$SOURCE_DIR/LICENSE" "$PACKAGE_DIR/LICENSE.jpegli"
cp "$SOURCE_DIR/third_party/highway/LICENSE" "$PACKAGE_DIR/LICENSE.highway"
cp "$SOURCE_DIR/third_party/libjpeg-turbo/LICENSE.md" "$PACKAGE_DIR/LICENSE.libjpeg-turbo.md"

echo "Built jpegli $(git -C "$SOURCE_DIR" rev-parse --short HEAD) into $PACKAGE_DIR"
