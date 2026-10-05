// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "auddio_whisper_engine",
    platforms: [
        .iOS("15.0")
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
            url: "https://github.com/ketanchoyal/auddio_whisper_engine/releases/download/whisper-v0.0.19/libauddio_whisper_ios.xcframework.zip",
            checksum: "27b797f5b5f542d8463f6030f9ff9518d195089b553d8b3e0fe029974afcbce4"
        )
    ]
)
