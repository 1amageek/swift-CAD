import CADCore
import Foundation
import Testing
@testable import CADKernel

/// Certified sketch curve intersections reported in each curve's natural parameter.
@Suite("Sketch curve intersector")
struct SketchCurveIntersectorTests {
    private let intersector = SketchCurveIntersector(tolerance: .standard)
    private let accuracy = 1.0e-12

    private func point(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    @Test func crossingLinesReportBothSegmentParameters() throws {
        let roots = try intersector.intersections(
            of: .line(start: point(0, 0), end: point(10, 0)),
            with: .line(start: point(6, -2), end: point(6, 4))
        )
        #expect(roots.count == 1)
        #expect(abs(roots[0].firstParameter - 0.6) < accuracy)
        #expect(abs(roots[0].secondParameter - 1.0 / 3.0) < accuracy)
        #expect(abs(roots[0].point.x - 6) < accuracy && abs(roots[0].point.y) < accuracy)
    }

    @Test func aShortLineMeetsTheTargetOnlyWhenExtended() throws {
        let target = SketchCurveGeometry2D.line(start: point(0, 0), end: point(10, 0))
        let cutter = SketchCurveGeometry2D.line(start: point(6, 2), end: point(6, 4))
        #expect(try intersector.intersections(of: target, with: cutter).isEmpty)

        let extended = try intersector.intersections(of: target, with: cutter, secondReach: .extended)
        #expect(extended.count == 1)
        #expect(abs(extended[0].firstParameter - 0.6) < accuracy)
        #expect(abs(extended[0].secondParameter + 1.0) < accuracy)
    }

    @Test func lineAndCircleReportSegmentFractionsAndPolarAngles() throws {
        let roots = try intersector.intersections(
            of: .line(start: point(-2, 0), end: point(2, 0)),
            with: .circle(center: point(0, 0), radius: 1)
        )
        #expect(roots.count == 2)
        #expect(abs(roots[0].firstParameter - 0.25) < accuracy)
        #expect(abs(roots[0].secondParameter - Double.pi) < accuracy)
        #expect(abs(roots[1].firstParameter - 0.75) < accuracy)
        #expect(abs(roots[1].secondParameter) < accuracy || abs(roots[1].secondParameter - 2 * Double.pi) < accuracy)
    }

    @Test func circlesCrossAtTheirPolarAngles() throws {
        let roots = try intersector.intersections(
            of: .circle(center: point(0, 0), radius: 1),
            with: .circle(center: point(1, 0), radius: 1)
        )
        #expect(roots.count == 2)
        #expect(abs(roots[0].firstParameter - Double.pi / 3) < accuracy)
        #expect(abs(roots[1].firstParameter - 5 * Double.pi / 3) < accuracy)
        #expect(abs(roots[0].secondParameter - 2 * Double.pi / 3) < accuracy)
    }

    @Test func anArcCutsOnlyInsideItsSweepUnlessExtended() throws {
        let upperHalf = SketchCurveGeometry2D.arc(center: point(0, 0), radius: 1, startAngle: 0, endAngle: Double.pi)
        let below = SketchCurveGeometry2D.line(start: point(-2, -0.5), end: point(2, -0.5))
        #expect(try intersector.intersections(of: below, with: upperHalf).isEmpty)

        let fullCircle = try intersector.intersections(of: below, with: upperHalf, secondReach: .extended)
        #expect(fullCircle.count == 2)
        for root in fullCircle {
            #expect(root.secondParameter > Double.pi)
        }
    }

    @Test func aTangencyTheIntersectorCannotCertifyIsATypedFailure() {
        // The tangent point is a double root; floating control points leave it uncertifiable.
        #expect(throws: KernelError.self) {
            _ = try intersector.intersections(
                of: .line(start: point(-2, 1), end: point(2, 1)),
                with: .circle(center: point(0, 0), radius: 1)
            )
        }
    }

    @Test func aBezierChainReportsItsChainParameter() throws {
        let chain = SketchCurveGeometry2D.cubicBezierChain(controlPoints: [
            point(0, 0), point(1, 2), point(2, 2), point(3, 0),
            point(4, -2), point(5, -2), point(6, 0),
        ])
        let roots = try intersector.intersections(
            of: chain,
            with: .line(start: point(-1, 1), end: point(7, 1))
        )
        #expect(roots.count == 2)
        #expect(roots.allSatisfy { $0.firstParameter > 0 && $0.firstParameter < 1 })
        let middle = try intersector.intersections(
            of: chain,
            with: .line(start: point(4.5, -3), end: point(4.5, 3))
        )
        #expect(middle.count == 1)
        #expect(abs(middle[0].firstParameter - 1.5) < accuracy)
        #expect(abs(middle[0].point.y + 1.5) < accuracy)
    }

    @Test func unsupportedReachAndUncertifiableOverlapsAreTypedFailures() {
        let chain = SketchCurveGeometry2D.cubicBezierChain(controlPoints: [
            point(0, 0), point(1, 2), point(2, 2), point(3, 0),
        ])
        #expect(throws: KernelError.self) {
            _ = try intersector.intersections(
                of: .line(start: point(0, 0), end: point(3, 0)), with: chain, secondReach: .extended
            )
        }
        #expect(throws: KernelError.self) {
            _ = try intersector.intersections(
                of: .line(start: point(0, 0), end: point(4, 0)),
                with: .line(start: point(1, 0), end: point(3, 0))
            )
        }
        #expect(throws: KernelError.self) {
            _ = try intersector.intersections(
                of: .circle(center: point(0, 0), radius: 0), with: chain
            )
        }
    }
}
