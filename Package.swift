// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Supervim",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SupervimCore", targets: ["SupervimCore"]),
        .library(name: "SupervimSystem", targets: ["SupervimSystem"]),
        .executable(name: "Supervim", targets: ["Supervim"]),
    ],
    targets: [
        .target(
            name: "SupervimCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "SupervimSystem",
            dependencies: ["SupervimCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Supervim",
            dependencies: ["SupervimCore", "SupervimSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SupervimCoreTests",
            dependencies: ["SupervimCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SupervimSystemTests",
            dependencies: ["SupervimCore", "SupervimSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
