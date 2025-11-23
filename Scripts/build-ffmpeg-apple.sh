#!/usr/bin/env bash
set -euo pipefail

# Config
FFMPEG_VERSION=${FFMPEG_VERSION:-7.1}        # override to bump
MIN_IOS=15.0
MIN_TVOS=15.0
MIN_VISIONOS=1.0
MIN_MACOS=12.0

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT/build/src/ffmpeg-$FFMPEG_VERSION"
BUILD_DIR="$ROOT/build/out"
XC_OUT="$ROOT/xcframeworks"
# Only one XCFramework should carry headers to avoid duplicate installs in SwiftPM.
HEADER_CARRIER_LIB=${HEADER_CARRIER_LIB:-libavcodec}
# Extra flags help keep the generated objects within the platform page alignment
# limits so Xcode doesn't warn when reducing __DATA alignment.
EXTRA_FFMPEG_CFLAGS=${EXTRA_FFMPEG_CFLAGS:--fdata-sections -ffunction-sections -fmax-type-align=16}
EXTRA_FFMPEG_LDFLAGS=${EXTRA_FFMPEG_LDFLAGS:--Wl,-sectalign,__DATA,__common,0x4000 -framework Security -framework CoreFoundation}

# Targets: name arch sdk min-version
TARGETS_OVERRIDE=${TARGETS_OVERRIDE:-}
if [[ -n "$TARGETS_OVERRIDE" ]]; then
  TARGETS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    TARGETS+=("$line")
  done <<<"$TARGETS_OVERRIDE"
else
  TARGETS=(
    "ios        arm64   iphoneos         $MIN_IOS"
    "ios-sim    arm64   iphonesimulator  $MIN_IOS"
    "tvos       arm64   appletvos        $MIN_TVOS"
    "tvos-sim   arm64   appletvsimulator $MIN_TVOS"
    "visionos   arm64   xros             $MIN_VISIONOS"
    "visionos-sim arm64 xrsimulator      $MIN_VISIONOS"
    "macos      arm64   macosx           $MIN_MACOS"
    # Uncomment if you want Intel mac sim/support:
    # "macos      x86_64 macosx           $MIN_MACOS"
  )
fi

COMMON_CFG=(
  --enable-cross-compile
  --enable-static
  --disable-shared
  --disable-programs
  --disable-doc
  --enable-pic
  --disable-autodetect
  --enable-videotoolbox
  --enable-securetransport
  --disable-filter=zscale
  --enable-protocol=file,https,tcp,tls
  --enable-demuxer=mov,matroska,mpegts,hls,flv
  --enable-muxer=mp4,matroska,mpegts,hls,segment
  --enable-parser=h264,hevc,aac,ac3,eac3,truehd,dca
  --enable-decoder=h264,hevc,eac3,truehd,ac3,aac,alac,flac,opus,vorbis,mp3,dca,pcm_s16le,pcm_s24le,pgssub,ass,srt
  # zscale requires external libzimg; keep it disabled unless you add that dependency.
  --enable-filter=aresample,afloudnorm,anlmdn,pad,scale,scale_videotoolbox,tonemap
)

fetch_ffmpeg() {
  if [[ -d "$SRC_DIR" ]]; then return; fi
  mkdir -p "$ROOT/build/src"
  curl -L "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.bz2" -o "$ROOT/build/src/ffmpeg.tar.bz2"
  tar -xf "$ROOT/build/src/ffmpeg.tar.bz2" -C "$ROOT/build/src"
}

apply_patches() {
  local vt="$SRC_DIR/libavcodec/videotoolbox.c"
  if [[ -f "$vt" ]] && ! grep -q "#ifndef kCMVideoCodecType_HEVC" "$vt"; then
    # Newer SDKs already define these; guard to avoid enum redefinition errors.
    perl -0pi -e "s/enum \\{ kCMVideoCodecType_HEVC = 'hvc1' \\};/#ifndef kCMVideoCodecType_HEVC\\nenum { kCMVideoCodecType_HEVC = 'hvc1' };\\n#endif/" "$vt"
    perl -0pi -e "s/enum \\{ kCMVideoCodecType_VP9 = 'vp09' \\};/#ifndef kCMVideoCodecType_VP9\\nenum { kCMVideoCodecType_VP9 = 'vp09' };\\n#endif/" "$vt"
  fi
  # Force-disable redeclaration blocks if the SDK already ships the enums.
  perl -0pi -e "s/#if !HAVE_KCMVIDEOCODECTYPE_HEVC/#if 0/" "$vt"
  perl -0pi -e "s/#if !HAVE_KCMVIDEOCODECTYPE_VP9/#if 0/" "$vt"
  # visionOS: avoid OpenGLES compatibility key which is unavailable.
  perl -0pi -e "s/#if TARGET_OS_IPHONE\\n    CFDictionarySetValue\\(buffer_attributes, kCVPixelBufferOpenGLESCompatibilityKey, kCFBooleanTrue\\);/#if TARGET_OS_IPHONE \\&\\& !TARGET_OS_VISION\\n    CFDictionarySetValue(buffer_attributes, kCVPixelBufferOpenGLESCompatibilityKey, kCFBooleanTrue);/" "$vt"
  perl -0pi -e "s/#else\\n    CFDictionarySetValue\\(buffer_attributes, kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey, kCFBooleanTrue\\);/#elif !TARGET_OS_IPHONE\\n    CFDictionarySetValue(buffer_attributes, kCVPixelBufferIOSurfaceOpenGLTextureCompatibilityKey, kCFBooleanTrue);/" "$vt"

  local afftdn="$SRC_DIR/libavfilter/af_afftdn.c"
  if [[ -f "$afftdn" ]]; then
    perl -0pi -e 's/double sqr_new_gain, new_gain, power, mag, mag_abs_var, new_mag_abs_var;/double sqr_new_gain, new_gain, power, mag = 0.0, mag_abs_var, new_mag_abs_var;/' "$afftdn"
  fi
}

build_target() {
  local name="$1" arch="$2" sdk="$3" minver="$4"
  local sysroot
  sysroot="$(xcrun --sdk "$sdk" --show-sdk-path)"

  local cflags ldflags
  case "$sdk" in
    macosx)
      cflags="-arch $arch -mmacosx-version-min=$minver"
      ldflags="-arch $arch -mmacosx-version-min=$minver"
      ;;
    xros|xrsimulator)
      local target_suffix=""
      [[ "$sdk" == "xrsimulator" ]] && target_suffix="-simulator"
      local target="arm64-apple-xros${minver}${target_suffix}"
      cflags="-arch $arch -isysroot $sysroot -target $target"
      ldflags="-arch $arch -isysroot $sysroot -target $target"
      ;;
    iphoneos|iphonesimulator)
      local target_suffix=""
      [[ "$sdk" == "iphonesimulator" ]] && target_suffix="-simulator"
      local target="arm64-apple-ios${minver}${target_suffix}"
      cflags="-arch $arch -isysroot $sysroot -target $target"
      ldflags="-arch $arch -isysroot $sysroot -target $target"
      ;;
    appletvos|appletvsimulator)
      local target_suffix=""
      [[ "$sdk" == "appletvsimulator" ]] && target_suffix="-simulator"
      local target="arm64-apple-tvos${minver}${target_suffix}"
      cflags="-arch $arch -isysroot $sysroot -target $target"
      ldflags="-arch $arch -isysroot $sysroot -target $target"
      ;;
    *)
      echo "Unknown sdk $sdk"; exit 1;;
  esac

  local out="$BUILD_DIR/$name-$arch"
  mkdir -p "$out"
  pushd "$SRC_DIR" >/dev/null
  # Skip noisy distclean on a fresh tree with no config.mak.
  if [[ -f ffbuild/config.mak ]]; then
    make distclean
  fi

  local extra_cflags="$cflags $EXTRA_FFMPEG_CFLAGS"
  local extra_ldflags="$ldflags $EXTRA_FFMPEG_LDFLAGS"

  PKG_CONFIG_PATH="" \
  ./configure \
    --cc="$(xcrun --sdk "$sdk" --find clang)" \
    --sysroot="$sysroot" \
    --extra-cflags="$extra_cflags" \
    --extra-ldflags="$extra_ldflags" \
    --prefix="$out" \
    "${COMMON_CFG[@]}"

  make -j"$(sysctl -n hw.ncpu)"
  make install
  popd >/dev/null
}

create_xc() {
  local lib="$1"; shift
  local libs=("$@")
  xcodebuild -create-xcframework "${libs[@]}" -output "$XC_OUT/$lib.xcframework"
}

main() {
  fetch_ffmpeg
  apply_patches
  rm -rf "$XC_OUT"
  mkdir -p "$BUILD_DIR" "$XC_OUT"

  # Build all slices
  for entry in "${TARGETS[@]}"; do
    read -r name arch sdk minver <<<"$entry"
    echo "==> Building $name ($arch / $sdk)"
    build_target "$name" "$arch" "$sdk" "$minver"
  done

  # Collect per-lib slices into XCFrameworks
  local libs=(libavcodec libavformat libavutil libswresample libswscale libavfilter libavdevice)
  for lib in "${libs[@]}"; do
    echo "==> Creating $lib.xcframework"
    declare -a xcargs=()
    for entry in "${TARGETS[@]}"; do
      read -r name arch sdk minver <<<"$entry"
      local libpath="$BUILD_DIR/$name-$arch/lib/$lib.a"
      [[ -f "$libpath" ]] || continue
      if [[ "$lib" == "$HEADER_CARRIER_LIB" ]]; then
        xcargs+=(-library "$libpath" -headers "$BUILD_DIR/$name-$arch/include")
      else
        xcargs+=(-library "$libpath")
      fi
    done
    create_xc "$lib" "${xcargs[@]}"
  done

  echo "XCFrameworks at: $XC_OUT"
}

main "$@"
