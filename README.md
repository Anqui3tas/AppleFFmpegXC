# FFmpegBinaries

Prebuilt FFmpeg 7.1 XCFrameworks for Apple platforms (iOS, tvOS, macOS, visionOS), packaged for SwiftPM. The binaries are LGPL-friendly, decode-only, and built with VideoToolbox hardware acceleration. Use this package to drop FFmpeg into apps without rebuilding for every project.

## What’s included
- XCFrameworks: `libavcodec`, `libavdevice`, `libavfilter`, `libavformat`, `libavutil`, `libswresample`, `libswscale`
- Architectures: arm64 for devices + simulators across iOS/tvOS/visionOS, and arm64 for macOS
- Build flags: static libs, no FFmpeg CLI/tools, docs stripped, autodetect disabled, VideoToolbox enabled, common demuxers/muxers/parsers/decoders/filters for playback pipelines
- Patches: guards HEVC/VP9 enums in `videotoolbox.c` and skips OpenGLES compatibility on visionOS; `distclean` between targets to avoid cross-contamination

## Using in Xcode or SwiftPM
1. Add the repo as a Swift package.
2. Depend on the `FFmpeg` product:
   ```swift
   .package(url: "https://github.com/<org>/SwiftFFmpeg.git", branch: "main"),
   // ...
   .target(
       name: "YourApp",
       dependencies: [.product(name: "FFmpeg", package: "FFmpegBinaries")]
   )
   ```
3. Import `FFmpeg` in Swift to pull in the linked libs. Include the relevant `libav*` headers in your bridging header or C targets to call into FFmpeg.

## Rebuilding FFmpeg
Use `Scripts/build-ffmpeg-apple.sh` to refresh the XCFrameworks when FFmpeg updates:
```bash
./Scripts/build-ffmpeg-apple.sh
# or to bump versions:
FFMPEG_VERSION=7.2 ./Scripts/build-ffmpeg-apple.sh
```
By default only `libavcodec.xcframework` carries headers to avoid duplicate installs in SwiftPM. If you want a different carrier, set `HEADER_CARRIER_LIB=libavutil` (or another lib) when running the script.

The script downloads the release tarball, applies the VideoToolbox/visionOS fixes, builds every SDK slice with `-target arm64-apple-{ios,tvos,xros}{,-simulator}` (and macOS), runs `distclean` between targets, and emits fresh XCFrameworks into `xcframeworks/` used by `Package.swift`.

Requirements: Xcode command-line tools on macOS, `curl`, `perl`, and `xcodebuild`.

## Layout
- `Package.swift` – SwiftPM manifest exposing the `FFmpeg` library product
- `Sources/FFmpeg` – shim target to link the binary XCFrameworks
- `xcframeworks/` – prebuilt FFmpeg XCFrameworks consumed by SwiftPM
- `Scripts/build-ffmpeg-apple.sh` – reproducible build script (LGPL, decode-only, VideoToolbox)

## License
FFmpeg is licensed under LGPL. Because the binaries are static, ensure your app complies with LGPL requirements (e.g., relinking options and notices) when distributing.
