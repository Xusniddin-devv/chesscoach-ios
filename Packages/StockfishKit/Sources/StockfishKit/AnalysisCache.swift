import ChessCore

/// Remembers the last analysis only: re-asking for the position on screen is free, anything
/// else goes to the engine. Keyed by the whole request, so a different MultiPV misses.
struct AnalysisCache {
    private var entry: (request: AnalysisRequest, result: AnalysisResult)?

    mutating func get(_ r: AnalysisRequest) -> AnalysisResult? {
        entry?.request == r ? entry?.result : nil
    }

    mutating func put(_ r: AnalysisRequest, _ result: AnalysisResult) {
        entry = (r, result)
    }
}
