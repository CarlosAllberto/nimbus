#!/usr/bin/env bash
# Builds the minimal, LGPL-only ffmpeg that Compress Videos shells out to and
# writes it to Sources/Nimbus/Resources/ffmpeg.
#
#   brew install libvpx opus pkg-config nasm   # once
#   Tools/build-ffmpeg.sh
#
# Output: static (libvpx + libopus linked in), host architecture only, no GPL
# or nonfree code. Inputs: mov/mp4, matroska/webm, avi. Output: VP9 + Opus
# in WebM. Re-run it to rebuild; bump FFMPEG_VERSION + FFMPEG_SHA256 to upgrade.
#
# LGPL note: ffmpeg is LGPL-2.1+ and statically links libvpx/libopus (BSD).
# Shipping it means offering the ffmpeg source + this script (the "relink"
# obligation); keep this script and the pinned version in the repo for that.
#
# x86_64: Homebrew's libvpx/opus are arm64-only here, so this yields an arm64
# binary. For a universal app, run this on an Intel Mac (or under a /usr/local
# Homebrew via Rosetta) with OUT=... and merge with `lipo -create`.
set -euo pipefail

FFMPEG_VERSION=7.1.1
FFMPEG_SHA256=733984395e0dbbe5c046abda2dc49a5544e7e0e1e2366bba849222ae9e3a03b1
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)/Sources/Nimbus/Resources/ffmpeg}"

for tool in pkg-config nasm curl shasum; do
  command -v "$tool" >/dev/null || { echo "missing $tool (brew install libvpx opus pkg-config nasm)" >&2; exit 1; }
done
pkg-config --exists vpx opus || { echo "libvpx/opus not found by pkg-config (brew install libvpx opus)" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

# Homebrew ships .dylib next to .a and the linker prefers the dylib. Stage only
# the static archives (and .pc files pointing at them) so the result is
# self-contained.
deps="$work/deps"
mkdir -p "$deps/lib/pkgconfig" "$deps/include"
for lib in vpx opus; do
  prefix="$(pkg-config --variable=prefix $lib)"
  cp "$prefix/lib/lib$lib.a" "$deps/lib/"
  cp -R "$prefix/include/$lib" "$deps/include/"
  sed -e "s|^prefix=.*|prefix=$deps|" -e "s|^libdir=.*|libdir=$deps/lib|" "$prefix/lib/pkgconfig/$lib.pc" > "$deps/lib/pkgconfig/$lib.pc"
done
export PKG_CONFIG_PATH="$deps/lib/pkgconfig" PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig"

curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o ffmpeg.tar.xz
echo "$FFMPEG_SHA256  ffmpeg.tar.xz" | shasum -a 256 -c -
tar xf ffmpeg.tar.xz
cd "ffmpeg-$FFMPEG_VERSION"

./configure \
  --disable-gpl --disable-nonfree --disable-version3 \
  --disable-everything --disable-autodetect \
  --disable-doc --disable-debug --disable-network \
  --disable-ffplay --disable-ffprobe \
  --enable-static --disable-shared --pkg-config-flags=--static \
  --extra-cflags="-mmacosx-version-min=14.0" --extra-ldflags="-mmacosx-version-min=14.0" \
  --enable-libvpx --enable-libopus \
  --enable-protocol=file,pipe \
  --enable-demuxer=mov,matroska,avi,mp3,ogg,wav \
  --enable-muxer=webm \
  --enable-parser=h264,hevc,vp8,vp9,aac,aac_latm,mpegaudio,opus,vorbis \
  --enable-decoder=h264,hevc,vp8,vp9,mpeg4,aac,mp3,mp3float,opus,vorbis,flac,pcm_s16le,pcm_s24le,pcm_f32le \
  --enable-encoder=libvpx_vp9,libopus \
  --enable-filter=scale,aresample,format,aformat,null,anull \
  --enable-bsf=null,vp9_superframe

make -j"$(sysctl -n hw.ncpu)" ffmpeg
strip -x ffmpeg
mkdir -p "$(dirname "$OUT")"
install -m 755 ffmpeg "$OUT"
! otool -L "$OUT" | grep -q /opt/homebrew || { echo "binary still links Homebrew dylibs" >&2; exit 1; }
"$OUT" -version | head -3
