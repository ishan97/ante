// Packages/AnteUI/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnteUI",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnteUI", targets: ["AnteUI"]),
    ],
    dependencies: [
        .package(path: "../AnteCore"),
        .package(path: "../AnteTerm"),
        .package(path: "../AnteTheme"),
        .package(path: "../AntePanel"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.0.1"),
    ],
    targets: [
        .target(
            name: "AnteUI",
            dependencies: [
                .product(name: "AnteCore", package: "AnteCore"),
                .product(name: "AnteTerm", package: "AnteTerm"),
                .product(name: "AnteTheme", package: "AnteTheme"),
                .product(name: "AntePanel", package: "AntePanel"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AnteUITests",
            dependencies: ["AnteUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
