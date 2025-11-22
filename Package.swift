// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FFmpegBinaries",
    platforms: [.iOS(.v15), .tvOS(.v15), .macOS(.v12), .visionOS(.v1)],
    products: [.library(name: "FFmpeg", targets: ["FFmpeg"])],
    targets: [
        .binaryTarget(name: "libavcodec",    path: "xcframeworks/libavcodec.xcframework"),
        .binaryTarget(name: "libavdevice",   path: "xcframeworks/libavdevice.xcframework"),
        .binaryTarget(name: "libavfilter",   path: "xcframeworks/libavfilter.xcframework"),
        .binaryTarget(name: "libavformat",   path: "xcframeworks/libavformat.xcframework"),
        .binaryTarget(name: "libavutil",     path: "xcframeworks/libavutil.xcframework"),
        .binaryTarget(name: "libswresample", path: "xcframeworks/libswresample.xcframework"),
        .binaryTarget(name: "libswscale",    path: "xcframeworks/libswscale.xcframework"),
        .target(
            name: "FFmpeg",
            dependencies: [
                "libavcodec","libavdevice","libavfilter",
                "libavformat","libavutil","libswresample","libswscale"
            ]
        )
    ]
)
