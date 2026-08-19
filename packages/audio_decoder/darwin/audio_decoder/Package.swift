// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "audio_decoder",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "audio-decoder", targets: ["audio_decoder"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "audio_decoder",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
