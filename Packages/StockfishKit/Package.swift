// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StockfishKit",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [
        .library(name: "StockfishKit", targets: ["StockfishKit"]),
    ],
    dependencies: [
        .package(path: "../ChessCore"),
    ],
    targets: [
        // Stockfish 18 (GPLv3, vendored by scripts/vendor-stockfish.sh) plus the C bridge.
        // arm64 only: NEON is required (macOS on Apple silicon, iOS devices and simulators).
        .target(
            name: "StockfishCore",
            exclude: ["stockfish/Copying.txt", "stockfish/incbin/UNLICENCE"],
            cxxSettings: [
                .define("NNUE_EMBEDDING_OFF"),
                .define("USE_POPCNT"),
                .define("USE_NEON", to: "8"),
                .define("IS_64BIT"),
                .define("NDEBUG"),
                .unsafeFlags(["-O3"]),
            ]
        ),
        .target(
            name: "StockfishKit",
            dependencies: [
                "StockfishCore",
                .product(name: "ChessCore", package: "ChessCore"),
            ],
            resources: [.copy("Resources/nnue")]
        ),
        .testTarget(
            name: "StockfishKitTests",
            dependencies: ["StockfishKit", "StockfishCore"]
        ),
    ],
    swiftLanguageModes: [.v6],
    cxxLanguageStandard: .gnucxx17
)
