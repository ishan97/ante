// Packages/AntePanel/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AntePanel",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AntePanel", targets: ["AntePanel"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.0.1"),
    ],
    targets: [
        .target(
            name: "AntePanel",
            dependencies: [.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AntePanelTests",
            dependencies: ["AntePanel"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
