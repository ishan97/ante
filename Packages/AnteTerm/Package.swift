// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnteTerm",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnteTerm", targets: ["AnteTerm"]),
    ],
    dependencies: [
        .package(path: "../AnteCore"),
        .package(path: "../AnteTheme"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.20.0"),
    ],
    targets: [
        .target(
            name: "AnteTerm",
            dependencies: [
                .product(name: "AnteCore", package: "AnteCore"),
                .product(name: "AnteTheme", package: "AnteTheme"),
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            resources: [.copy("Resources/Integration")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AnteTermTests",
            dependencies: ["AnteTerm"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
