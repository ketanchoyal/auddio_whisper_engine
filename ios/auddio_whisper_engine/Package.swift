// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "auddio_whisper_engine",
    platforms: [
        .iOS("16.4")
    ],
    products: [
        .library(
            name: "auddio-whisper-engine",
            targets: ["auddio_whisper_engine"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "auddio_whisper_engine",
            dependencies: [
                .target(name: "auddio_whisper")
            ],
            path: "Sources"
        ),
        .binaryTarget(
            name: "auddio_whisper",
            url: "https://github.com/ketanchoyal/auddio_whisper_engine/releases/download/whisper-v0.0.9/libauddio_whisper_ios.xcframework.zip",
            checksum: "813754b9a78f3f5f17289355a337c3335cb5b301d6db0f863b81dac0ca0645c3"
        )
    ]
)
