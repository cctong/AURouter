// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AURouter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AURouterCore", targets: ["AURouterCore"]),
        .executable(name: "AURouter", targets: ["AURouterApp"])
    ],
    targets: [
        .target(
            name: "AURouterRealtime",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("Foundation")
            ]
        ),
        .target(
            name: "AURouterCore",
            dependencies: ["AURouterRealtime"],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFAudio"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .executableTarget(
            name: "AURouterApp",
            dependencies: ["AURouterCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreAudioKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "AURouterCoreTests",
            dependencies: ["AURouterCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
