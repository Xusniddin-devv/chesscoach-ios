import CoreGraphics
import Testing
@testable import ChessCore

@Test func geometryBothOrientations() {
    #expect(BoardGeometry.rect(for: .a1, orientation: .white, side: 800) == CGRect(x: 0, y: 700, width: 100, height: 100))
    #expect(BoardGeometry.rect(for: .a1, orientation: .black, side: 800) == CGRect(x: 700, y: 0, width: 100, height: 100))
    #expect(BoardGeometry.square(at: CGPoint(x: 750, y: 50), orientation: .white, side: 800) == .h8)
    #expect(BoardGeometry.square(at: CGPoint(x: 801, y: 50), orientation: .white, side: 800) == nil)
}
