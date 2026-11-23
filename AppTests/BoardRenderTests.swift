import Testing
import SwiftUI
import UIKit
@testable import ChessCoach

/// Writes the board preview to docs/design/screens/plan1-board.png for visual review.
/// Off by default; run with `TEST_RUNNER_RENDER_SCREENS=1 xcodebuild test …`.
@MainActor
struct BoardRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RENDER_SCREENS"] == "1"))
    func renderNg5Blunder() throws {
        let content = BoardSamples.ng5Blunder
            .frame(width: 402)
            .padding(.vertical, DS.Spacing.m)
            .background(DS.Color.background)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let png = try #require(renderer.uiImage?.pngData())
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        try png.write(to: repo.appending(path: "docs/design/screens/plan1-board.png"))
    }
}
