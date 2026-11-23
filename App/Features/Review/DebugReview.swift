#if DEBUG
import Foundation
import ChessCore
import StockfishKit

/// DEBUG-only launch arguments for Review screenshots:
///   -debugReview latest        opens the most recent saved game in Review (from Home)
///   -debugReviewPly blunder    once analysed, selects the user's first blunder (else any
///                              blunder, else the first negative move) and shows the best
///                              move; a number selects that ply
///   -debugReviewBranch 1       then tries the best move instead and the engine's reply
///   -debugReviewList 1         then opens the move list
@MainActor
enum DebugReview {
    static var requested: Bool { UserDefaults.standard.string(forKey: "debugReview") != nil }

    private static func log(_ s: String) { print("REVIEW \(s)") }

    static func apply(to model: ReviewModel) async {
        guard requested, let analysis = model.analysis else { return }
        log("analysed \(analysis.verdicts.count)")
        guard let choice = UserDefaults.standard.string(forKey: "debugReviewPly") else { return }
        let verdicts = analysis.verdicts
        let user = model.snapshot.userColor
        let picked: Verdict? = Int(choice).flatMap { ply in verdicts.first { $0.ply == ply } }
            ?? verdicts.first { $0.mover == user && $0.classification == .blunder }
            ?? verdicts.first { $0.classification == .blunder }
            ?? verdicts.first { $0.classification.isNegative }
        guard let verdict = picked else { return }
        model.select(ply: verdict.ply)
        model.showsBest = true
        log("selected \(verdict.ply) \(verdict.san) \(verdict.classification.rawValue)")

        guard UserDefaults.standard.string(forKey: "debugReviewBranch") != nil else { return }
        try? await Task.sleep(for: .seconds(5))
        model.select(ply: verdict.ply - 1)
        guard model.playBranchMove(verdict.bestMove) else { return }
        log("branch \(verdict.bestMove)")
        let request = AnalysisRequest(startFen: model.snapshot.startFen, moves: model.currentLine,
                                      depth: 10, multiPV: 1)
        if let reply = try? await StockfishEngine.shared.analyze(request).bestMove, !reply.isEmpty {
            try? await Task.sleep(for: .seconds(1))
            model.playBranchMove(reply)
            log("branch reply \(reply)")
        }
    }
}
#endif
