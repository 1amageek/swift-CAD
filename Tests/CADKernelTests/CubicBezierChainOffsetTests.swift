import Foundation
import Testing
@testable import CADKernel
import CADCore

/// A cubic chain's offset stays at the distance from it, within the modeling distance.
@Suite struct CubicBezierChainOffsetTests {
    private let offsetter = CubicBezierChainOffset(tolerance: .standard)

    private func point(_ chain: [Point2D], _ parameter: Double) -> Point2D {
        let spans = (chain.count - 1) / 3
        let span = min(Int(parameter), spans - 1)
        let t = parameter - Double(span)
        let p = Array(chain[(3 * span)...(3 * span + 3)])
        let s = 1 - t
        return Point2D(
            x: s * s * s * p[0].x + 3 * s * s * t * p[1].x + 3 * s * t * t * p[2].x + t * t * t * p[3].x,
            y: s * s * s * p[0].y + 3 * s * s * t * p[1].y + 3 * s * t * t * p[2].y + t * t * t * p[3].y
        )
    }

    /// The largest gap between the offset's distance to `source` and |distance|.
    private func deviation(_ offset: [Point2D], from source: [Point2D], distance: Double) -> Double {
        let sourceSpans = Double((source.count - 1) / 3)
        let dense = (0...4000).map { point(source, sourceSpans * Double($0) / 4000) }
        let offsetSpans = Double((offset.count - 1) / 3)
        var worst = 0.0
        for i in 1..<200 {
            let q = point(offset, offsetSpans * Double(i) / 200)
            let nearest = dense.map { (($0.x - q.x) * ($0.x - q.x) + ($0.y - q.y) * ($0.y - q.y)).squareRoot() }.min()!
            worst = max(worst, abs(nearest - abs(distance)))
        }
        return worst
    }

    @Test func aStraightChainMovesAlongItsNormal() throws {
        let line = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 2, y: 0), Point2D(x: 3, y: 0)]
        let offset = try offsetter.offset(of: line, distance: 0.5)
        #expect(offset.count == 4)
        #expect(offset.allSatisfy { abs($0.y - 0.5) < 1e-12 })
    }

    @Test func aCurvedChainStaysAtTheDistance() throws {
        // Two spans turning left then right, G1 at the joint.
        let chain = [
            Point2D(x: 0, y: 0), Point2D(x: 0.01, y: 0.02), Point2D(x: 0.03, y: 0.02), Point2D(x: 0.04, y: 0),
            Point2D(x: 0.05, y: -0.02), Point2D(x: 0.07, y: -0.02), Point2D(x: 0.08, y: 0),
        ]
        for distance in [0.002, -0.003] {
            let offset = try offsetter.offset(of: chain, distance: distance)
            #expect((offset.count - 1).isMultiple(of: 3))
            #expect(deviation(offset, from: chain, distance: distance) < 5e-6)
        }
    }

    @Test func aCornerOrAFoldIsRefused() {
        let cornered = [
            Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 2, y: 0), Point2D(x: 3, y: 0),
            Point2D(x: 3, y: 1), Point2D(x: 3, y: 2), Point2D(x: 3, y: 3),
        ]
        #expect(throws: KernelError.self) { _ = try offsetter.offset(of: cornered, distance: 0.1) }
        // A tight left turn offset to its left past its radius of curvature folds back.
        let tight = [Point2D(x: 0, y: 0), Point2D(x: 0.01, y: 0), Point2D(x: 0.01, y: 0.01), Point2D(x: 0, y: 0.01)]
        #expect(throws: KernelError.self) { _ = try offsetter.offset(of: tight, distance: 0.05) }
    }
}
