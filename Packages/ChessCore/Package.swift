// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChessCore",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [
        .library(name: "ChessCore", targets: ["ChessCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/chesskit-studio/chesskit-swift", exact: "0.17.0"),
    ],
    targets: [
        .target(
            name: "ChessCore",
            dependencies: [.product(name: "ChessKit", package: "chesskit-swift")]
        ),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"]),
    ],
    swiftLanguageModes: [.v6]
)
