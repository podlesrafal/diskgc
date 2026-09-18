// swift-tools-version: 6.0
import PackageDescription

let swift5 = [SwiftSetting.swiftLanguageMode(.v5)]

let package = Package(
    name: "diskgc",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "diskgc", targets: ["diskgc"]),
        .executable(name: "DiskGCBar", targets: ["DiskGCBar"]),
        .library(name: "DiskGCCore", targets: ["DiskGCCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(name: "DiskGCCore", dependencies: ["Yams"], swiftSettings: swift5),
        .executableTarget(
            name: "diskgc",
            dependencies: [
                "DiskGCCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: swift5
        ),
        .executableTarget(name: "DiskGCBar", dependencies: ["DiskGCCore"], swiftSettings: swift5),
        .testTarget(name: "DiskGCCoreTests", dependencies: ["DiskGCCore"], swiftSettings: swift5),
    ]
)
