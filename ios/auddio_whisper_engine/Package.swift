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
            url: "https://github.com/ketanchoyal/auddio_whisper_engine/releases/download/whisper-v0.0.15/libauddio_whisper_ios.xcframework.zip",
            checksum: "346d3683bc77c41967145e2e64ead87e11a4b03a048ee27cd9a4ffafa1b05085"
        )
    ]
)
