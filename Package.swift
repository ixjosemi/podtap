// swift-tools-version: 6.0
import PackageDescription

// Modules that talk to IOKit, CoreGraphics and AppKit use Swift 5 language
// mode: C callbacks and AppKit APIs are not annotated for Swift 6 strict
// concurrency, and forcing it there would only add noise. `GestureCore`, which
// is pure, does compile in Swift 6 mode.
let legacyConcurrency: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "PodTap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PodTap", targets: ["PodTapApp"]),
        .library(name: "GestureCore", targets: ["GestureCore"]),
    ],
    targets: [
        // Pure gesture classification. No IOKit, no CoreGraphics, no real clock:
        // everything is injected, so it tests without hardware.
        .target(name: "GestureCore", path: "Sources/GestureCore"),

        // Event synthesis towards the system.
        .target(
            name: "KeyOutput",
            path: "Sources/KeyOutput",
            swiftSettings: legacyConcurrency
        ),

        // Exclusive capture of the remote button.
        .target(
            name: "HIDInput",
            path: "Sources/HIDInput",
            swiftSettings: legacyConcurrency
        ),

        .executableTarget(
            name: "PodTapApp",
            dependencies: ["GestureCore", "KeyOutput", "HIDInput"],
            path: "Sources/PodTapApp",
            swiftSettings: legacyConcurrency
        ),

        .testTarget(
            name: "GestureCoreTests",
            dependencies: ["GestureCore"],
            path: "tests/GestureCoreTests"
        ),
        .testTarget(
            name: "KeyOutputTests",
            dependencies: ["KeyOutput"],
            path: "tests/KeyOutputTests",
            swiftSettings: legacyConcurrency
        ),
    ]
)
