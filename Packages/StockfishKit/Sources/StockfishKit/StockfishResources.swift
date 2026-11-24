import Foundation

/// Locates the bundled NNUE nets (fetched by scripts/fetch-nnue.sh).
public enum StockfishResources {
    public static let bigNetName = "nn-c288c895ea92.nnue"
    public static let smallNetName = "nn-37f18f62d772.nnue"

    /// Absolute paths for the `EvalFile` and `EvalFileSmall` UCI options.
    /// Stops here if a net is missing or empty: Stockfish would otherwise exit the process
    /// on the first `go`.
    public static func netPaths() -> (big: String, small: String) {
        guard let directory = Bundle.module.url(forResource: "nnue", withExtension: nil) else {
            preconditionFailure("nnue resources missing; run scripts/fetch-nnue.sh")
        }
        let big = directory.appending(path: bigNetName).path(percentEncoded: false)
        let small = directory.appending(path: smallNetName).path(percentEncoded: false)
        guard isNonEmptyFile(big), isNonEmptyFile(small) else {
            preconditionFailure("nnue resources missing; run scripts/fetch-nnue.sh")
        }
        return (big, small)
    }

    private static func isNonEmptyFile(_ path: String) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        return size > 0
    }
}
