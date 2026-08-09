// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PodTap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GestureCore", targets: ["GestureCore"])
    ],
    targets: [
        // Lógica pura de clasificación de gestos. Sin IOKit, sin CoreGraphics,
        // sin reloj real: todo se inyecta, así que se testea sin hardware.
        .target(name: "GestureCore", path: "Sources/GestureCore"),
        .testTarget(
            name: "GestureCoreTests",
            dependencies: ["GestureCore"],
            path: "tests/GestureCoreTests"
        ),
    ]
)
