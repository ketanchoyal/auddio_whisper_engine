// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "auddio_whisper_engine",
    platforms: [
        .macOS("13.3")
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
            url: "https://github.com/ketanchoyal/auddio_whisper_engine/releases/download/whisper-v0.0.11/libauddio_whisper_macos.xcframework.zip",
            checksum: "425a3c8ef0f47b3b5f01e93a4111723117c01d250bef1f5bb9e046d6331509ec"
        )
    ]
)
