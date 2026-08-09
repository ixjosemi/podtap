// swift-tools-version: 6.0
import PackageDescription

// Los módulos que hablan con IOKit, CoreGraphics y AppKit usan el modo de
// lenguaje 5: las callbacks de C y las APIs de AppKit no están anotadas para la
// concurrencia estricta de Swift 6, y forzarla ahí solo añadiría ruido.
// `GestureCore`, que es puro, sí se compila en modo 6.
let legacyConcurrency: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "PodTap",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PodTap", targets: ["PodTapApp"]),
        .library(name: "GestureCore", targets: ["GestureCore"]),
    ],
    targets: [
        // Lógica pura de clasificación de gestos. Sin IOKit, sin CoreGraphics,
        // sin reloj real: todo se inyecta, así que se testea sin hardware.
        .target(name: "GestureCore", path: "Sources/GestureCore"),

        // Síntesis de eventos hacia el sistema.
        .target(
            name: "KeyOutput",
            path: "Sources/KeyOutput",
            swiftSettings: legacyConcurrency
        ),

        // Captura exclusiva del botón del mando.
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
