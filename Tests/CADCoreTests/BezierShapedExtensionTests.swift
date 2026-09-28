import Foundation
import Testing
@testable import CADCore

/// Extend Curve's Arc, Soft and Reflective shapes evaluated from the curve's own Bezier points,
/// with the structure fixed when the extension was made.
@Suite struct BezierShapedExtensionTests {
    private let extender = BezierShapedExtension(tolerance: .standard)

    private func p(_ x: Double, _ y: Double) -> Point2D { Point2D(x: x, y: y) }

    private func evaluate(_ points: [Point2D], _ t: Double) -> Point2D {
        var level = points
        while level.count > 1 {
            level = zip(level, level.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }
        }
        return level[0]
    }

    /// An arc extension of a cubic end segment keeps its span count, raises its spans to the
    /// segment's degree and starts along the end's tangent; the same points come from the
    /// adaptive profile extension.
    @Test func anArcExtensionKeepsItsSpansAndMatchesTheProfile() throws {
        let segment = [p(0, 0), p(0.004, 0.002), p(0.008, 0.001), p(0.01, 0.004)]
        let count = try extender.profileSpanCount(segment: segment, length: 0.012, profile: .arc)
        let points = try extender.newPoints(shape: .arc(spanCount: count), controlPoints: segment, length: 0.012)
        #expect(points.count == 3 * count)
        let end = segment[3], before = segment[2]
        let tangent = atan2(end.y - before.y, end.x - before.x)
        #expect(abs(atan2(points[0].y - end.y, points[0].x - end.x) - tangent) < 1e-12)

        let quintic = [p(0, 0), p(0.002, 0.003), p(0.004, 0.001), p(0.006, 0.004), p(0.008, 0.002), p(0.01, 0.003)]
        let softCount = try extender.profileSpanCount(segment: quintic, length: 0.01, profile: .soft)
        #expect(try extender.newPoints(shape: .soft(spanCount: softCount), controlPoints: quintic, length: 0.01).count == 5 * softCount)
    }

    /// A span count too small for the changed input fails instead of changing the structure.
    @Test func tooFewStoredSpansFail() throws {
        let segment = [p(0, 0), p(0.001, 0), p(0.002, 0.0002), p(0.003, 0.0006)]
        let count = try extender.profileSpanCount(segment: segment, length: 0.001, profile: .arc)
        #expect(throws: KernelError.self) {
            try extender.newPoints(shape: .arc(spanCount: count), controlPoints: segment, length: 0.05)
        }
    }

    /// Reflective mirrors the curve's last length across the end's normal: every new point
    /// reflected back lies on the original, and the far end is the point the length reaches.
    @Test func reflectiveMirrorsTheTailOfTheStoredSegments() throws {
        let chain = [p(0, 0), p(0.003, 0.004), p(0.006, 0.004), p(0.009, 0.002), p(0.012, 0), p(0.015, 0.001), p(0.018, 0.003)]
        let stored = try extender.reflectiveSegmentCount(segments: chain, degree: 3, length: 0.005)
        #expect(stored.count == 1 && stored.coversCurve == false)
        let segments = Array(chain.suffix(4))
        let points = try extender.newPoints(shape: .reflective(degree: 3, coversCurve: false), controlPoints: segments, length: 0.005)
        #expect(points.count == 3)
        let end = segments[3], before = segments[2]
        let length = hypot(end.x - before.x, end.y - before.y)
        let t = Point2D(x: (end.x - before.x) / length, y: (end.y - before.y) / length)
        func mirrored(_ q: Point2D) -> Point2D {
            let along = (q.x - end.x) * t.x + (q.y - end.y) * t.y
            return p(q.x - 2 * along * t.x, q.y - 2 * along * t.y)
        }
        let back = [end] + points
        for i in 0...20 {
            let q = mirrored(evaluate(back, Double(i) / 20))
            let nearest = (0...40_000).map { evaluate(segments, Double($0) / 40_000) }.map { hypot($0.x - q.x, $0.y - q.y) }.min() ?? .infinity
            #expect(nearest < 2e-7)
        }
        // Longer than the stored segment: refused; the whole chain stored covers it.
        #expect(throws: KernelError.self) {
            try extender.newPoints(shape: .reflective(degree: 3, coversCurve: false), controlPoints: segments, length: 0.02)
        }
        let whole = try extender.newPoints(shape: .reflective(degree: 3, coversCurve: true), controlPoints: chain, length: 1)
        #expect(whole.count == 6)
        let far = mirrored(whole[5])
        #expect(hypot(far.x, far.y) < 1e-12)
        // Two stored segments whose tail now starts in the later one: refused.
        #expect(throws: KernelError.self) {
            try extender.newPoints(shape: .reflective(degree: 3, coversCurve: true), controlPoints: chain, length: 0.001)
        }
    }

    @Test func theExpressionRoundTripsAndRefusesMalformedForms() throws {
        let coordinates = [p(0, 0), p(0.004, 0.002), p(0.008, 0.001), p(0.01, 0.004)].flatMap {
            [CADExpression.constant(Quantity(value: $0.x, kind: .length)), .constant(Quantity(value: $0.y, kind: .length))]
        }
        let expression = CADExpression.bezierShapedExtension(
            shape: .soft(spanCount: 2), coordinates: coordinates,
            length: .constant(Quantity(value: 0.01, kind: .length)), coordinateIndex: 11
        )
        let data = try JSONEncoder().encode(expression)
        #expect(try JSONDecoder().decode(CADExpression.self, from: data) == expression)
        #expect(throws: KernelError.self) {
            try BezierShapedExtension.validateCoordinateForm(shape: .soft(spanCount: 2), count: coordinates.count, index: 12)
        }
        #expect(throws: KernelError.self) {
            try BezierShapedExtension.validateCoordinateForm(shape: .reflective(degree: 2, coversCurve: true), count: coordinates.count, index: 0)
        }
    }
}
