import Foundation

/// Locates the bundled NNUE nets (fetched by scripts/fetch-nnue.sh).
public enum StockfishResources {
    public static let bigNetName = "nn-c288c895ea92.nnue"
    public static let smallNetName = "nn-37f18f62d772.nnue"

    /// Absolute paths for the `EvalFile` and `EvalFileSmall` UCI options.
    public static func netPaths() -> (big: String, small: String) {
        guard let directory = Bundle.module.url(forResource: "nnue", withExtension: nil) else {
            preconditionFailure("nnue resources missing; run scripts/fetch-nnue.sh")
        }
        return (
            directory.appending(path: bigNetName).path(percentEncoded: false),
            directory.appending(path: smallNetName).path(percentEncoded: false)
        )
    }
}
