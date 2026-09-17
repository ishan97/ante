// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnteCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnteCore", targets: ["AnteCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "AnteCore",
            dependencies: [.product(name: "TOMLKit", package: "TOMLKit")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AnteCoreTests",
            dependencies: ["AnteCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
