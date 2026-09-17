// Packages/AnteTheme/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnteTheme",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnteTheme", targets: ["AnteTheme"]),
    ],
    dependencies: [
        .package(path: "../AnteCore"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", exact: "0.6.0"),
    ],
    targets: [
        .target(
            name: "AnteTheme",
            dependencies: [
                .product(name: "AnteCore", package: "AnteCore"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ],
            resources: [.copy("Resources/Themes"), .copy("Resources/Fonts")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AnteThemeTests",
            dependencies: ["AnteTheme"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
