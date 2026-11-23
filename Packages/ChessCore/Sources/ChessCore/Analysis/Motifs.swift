public enum Motif: String, Codable, Sendable, Equatable {
    case allowedMate = "allowed-mate"
    case missedMate = "missed-mate"
    case hangingPiece = "hanging-piece"
    case allowedFork = "allowed-fork"
    case missedCapture = "missed-capture"
    case openingPrinciple = "opening-principle"
}

/// Stub; Task 7 implements the motif rules.
public func detectMotifs(_ f: MoveFacts) -> [Motif] { [] }
