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

    /// A spline of another degree or with explicit knots is offset through its own Bezier
    /// segments: the offset stays at the distance from that curve, not from the cubic chain its
    /// control points would make.
    @Test func aSplineOfAnyDegreeIsOffsetOnItsOwnCurve() throws {
        let cases: [(degree: Int, knots: [Double]?, points: [Point2D])] = [
            (6, nil, [(0, 0), (0.01, 0), (0.02, 0), (0.03, 0.005), (0.06, 0.03), (0.06, 0.02), (0.06, 0.03)]),
            (5, nil, [(0, 0), (0.01, 0.02), (0.03, 0.025), (0.05, 0.02), (0.07, 0.01), (0.08, 0)]),
            (3, [0, 0, 0, 0, 0.4, 1, 1, 1, 1], [(0, 0), (0.01, 0.01), (0.02, 0.015), (0.03, 0.002), (0.04, 0.01)]),
        ].map { ($0.0, $0.1, $0.2.map { Point2D(x: $0.0, y: $0.1) }) }
        for testCase in cases {
            let curve = try SketchSplineCurve(degree: testCase.degree, knots: testCase.knots, controlPoints: testCase.points, tolerance: .standard)
            let lower = curve.bSpline.knots.first!, upper = curve.bSpline.knots.last!
            let dense = try (0...8000).map { try curve.bSpline.point(at: lower + (upper - lower) * Double($0) / 8000, tolerance: .standard) }
            for distance in [0.001, -0.0015] {
                let offset = try offsetter.offset(of: curve, distance: distance, gapFill: nil)
                #expect((offset.count - 1).isMultiple(of: 3))
                let offsetSpans = Double((offset.count - 1) / 3)
                var worst = 0.0
                for i in 1..<200 {
                    let q = point(offset, offsetSpans * Double(i) / 200)
                    let nearest = dense.map { (($0.x - q.x) * ($0.x - q.x) + ($0.y - q.y) * ($0.y - q.y)).squareRoot() }.min()!
                    worst = max(worst, abs(nearest - abs(distance)))
                }
                #expect(worst < 5e-6, "degree \(testCase.degree) distance \(distance): \(worst)")
            }
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

/// Corners: the offsets are trimmed where they cross and joined by the gap fill where they part.
@Suite struct CubicBezierChainOffsetGapFillTests {
    private let offsetter = CubicBezierChainOffset(tolerance: .standard)

    private func straight(_ a: Point2D, _ b: Point2D) -> [Point2D] {
        [a, Point2D(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3),
         Point2D(x: a.x + 2 * (b.x - a.x) / 3, y: a.y + 2 * (b.y - a.y) / 3), b]
    }

    private func polyline(_ points: [Point2D]) -> [Point2D] {
        var chain = [points[0]]
        for (a, b) in zip(points, points.dropFirst()) { chain += straight(a, b).dropFirst() }
        return chain
    }

    private func near(_ a: Point2D, _ x: Double, _ y: Double) -> Bool {
        abs(a.x - x) < 1e-9 && abs(a.y - y) < 1e-9
    }

    /// Every point the chain's control points include at a span joint.
    private func joints(_ chain: [Point2D]) -> [Point2D] {
        stride(from: 0, to: chain.count, by: 3).map { chain[$0] }
    }

    @Test func theInsideOfATurnIsTrimmedWhereItsOffsetsCross() throws {
        let l = polyline([Point2D(x: 0, y: 0), Point2D(x: 3, y: 0), Point2D(x: 3, y: 3)])
        let inside = try offsetter.offset(of: l, distance: 0.5, gapFill: .round)
        #expect(near(inside[0], 0, 0.5))
        #expect(near(inside[inside.count - 1], 2.5, 3))
        #expect(joints(inside).contains { near($0, 2.5, 0.5) })
    }

    @Test func theOutsideOfATurnIsFilledRoundOrLinear() throws {
        let l = polyline([Point2D(x: 0, y: 0), Point2D(x: 3, y: 0), Point2D(x: 3, y: 3)])
        let round = try offsetter.offset(of: l, distance: -0.5, gapFill: .round)
        #expect(near(round[0], 0, -0.5) && near(round[round.count - 1], 3.5, 3))
        // Every point of the round fill lies at the distance from the corner.
        let fill = joints(round).filter { $0.x > 3 - 1e-9 && $0.y < 1e-9 }
        #expect(!fill.isEmpty && fill.allSatisfy { abs(hypot($0.x - 3, $0.y) - 0.5) < 1e-9 })
        let linear = try offsetter.offset(of: l, distance: -0.5, gapFill: .linear)
        #expect(joints(linear).contains { near($0, 3.5, -0.5) })
        #expect(throws: KernelError.self) { _ = try offsetter.offset(of: l, distance: -0.5, gapFill: nil) }
    }

    @Test func aClosedSquareStaysClosedInsideAndOutside() throws {
        let square = polyline([Point2D(x: 0, y: 0), Point2D(x: 2, y: 0), Point2D(x: 2, y: 2), Point2D(x: 0, y: 2), Point2D(x: 0, y: 0)])
        let inside = try offsetter.offset(of: square, distance: 0.25, gapFill: .linear)
        #expect(inside.first == inside.last)
        for corner in [(0.25, 0.25), (1.75, 0.25), (1.75, 1.75), (0.25, 1.75)] {
            #expect(joints(inside).contains { near($0, corner.0, corner.1) })
        }
        let outside = try offsetter.offset(of: square, distance: -0.25, gapFill: .linear)
        #expect(outside.first == outside.last)
        for corner in [(-0.25, -0.25), (2.25, -0.25), (2.25, 2.25), (-0.25, 2.25)] {
            #expect(joints(outside).contains { near($0, corner.0, corner.1) })
        }
    }

    /// A closed loop smooth everywhere but at its seam keeps one corner, which is joined too.
    @Test func aLoopWithOneCornerAtItsSeamIsJoinedThere() throws {
        let leaf = [
            Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), Point2D(x: 3, y: 2), Point2D(x: 4, y: 0),
            Point2D(x: 5, y: -2), Point2D(x: 1, y: -3), Point2D(x: 0, y: 0),
        ]
        for distance in [0.1, -0.1] {
            let offset = try offsetter.offset(of: leaf, distance: distance, gapFill: .round)
            #expect(offset.first == offset.last)
            #expect((offset.count - 1).isMultiple(of: 3))
        }
    }
}
