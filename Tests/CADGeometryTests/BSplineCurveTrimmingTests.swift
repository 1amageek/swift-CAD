import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("B-spline Curve Trimming")
struct BSplineCurveTrimmingTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func bezierExtractionAndTrimsPreserveUnchangedControls() throws {
        let curve = BSplineCurve3D(degree: 2, knots: [0, 0, 0, 1, 1, 1],
            controlPoints: [Point3D(x: 0.1, y: 0.3, z: 0.7),
                Point3D(x: 0.4, y: 0.8, z: -0.2),
                Point3D(x: 0.9, y: -0.4, z: 0.6)],
            weights: [0.7, 1.3, 0.9])
        let patches = try BSplineCurveBezierDecomposer().curvePatches(curve: curve, tolerance: tolerance)
        let patch = try #require(patches.first)
        #expect(patches.count == 1)
        #expect(patch.controlPoints == curve.controlPoints)
        #expect(patch.weights == curve.weights)
        let unchanged = try patch.trimmed(from: 0, to: 1, tolerance: tolerance)
        #expect(unchanged.controlPoints == curve.controlPoints)
        #expect(unchanged.weights == curve.weights)
        let head = try curve.trimmed(from: 0, to: 0.37, tolerance: tolerance)
        let tail = try curve.trimmed(from: 0.37, to: 1, tolerance: tolerance)
        #expect(head.controlPoints.first == curve.controlPoints.first)
        #expect(tail.controlPoints.last == curve.controlPoints.last)
        #expect(head.controlPoints.last == tail.controlPoints.first)
        #expect(head.weights.last == tail.weights.first)
        var invalid = curve
        invalid.weights[0] = 0
        #expect(throws: (any Error).self) {
            _ = try BSplineCurveBezierDecomposer().curvePatches(curve: invalid, tolerance: tolerance)
        }
        let invalidPatch = RationalBezierCurvePatch3D(controlPoints: curve.controlPoints,
            weights: invalid.weights, lower: 0, upper: 1)
        #expect(throws: KernelError.self) {
            _ = try invalidPatch.trimmed(from: 0, to: 1, tolerance: tolerance)
        }
        var overflowing = curve
        overflowing.knots = Array(repeating: -Double.greatestFiniteMagnitude, count: 3)
            + Array(repeating: Double.greatestFiniteMagnitude, count: 3)
        #expect(throws: GeometryError.self) {
            _ = try BSplineCurveBezierDecomposer().curvePatches(curve: overflowing, tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalQuadraticTrimsPreserveExactTwoAndThreeDimensionalEvaluation() throws {
        let knots = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
        let weights = [1.0, 0.5, 2.0]
        let curve2D = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.5, y: 1.0),
                Point2D(x: 1.0, y: 0.0),
            ],
            weights: weights
        )
        let curve3D = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.5, y: 1.0, z: 0.25),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
            ],
            weights: weights
        )

        let trimmed2D = try curve2D.trimmed(from: 0.25, to: 0.75, tolerance: tolerance)
        let trimmed3D = try curve3D.trimmed(from: 0.25, to: 0.75, tolerance: tolerance)

        #expect(trimmed2D.domain == .closed(0.25, 0.75))
        #expect(trimmed3D.domain == .closed(0.25, 0.75))
        #expect(trimmed2D.isRational)
        #expect(trimmed3D.isRational)
        for parameter in [0.25, 0.375, 0.5, 0.625, 0.75] {
            let original2D = try curve2D.point(at: parameter, tolerance: tolerance)
            let result2D = try trimmed2D.point(at: parameter, tolerance: tolerance)
            #expect(hypot(original2D.x - result2D.x, original2D.y - result2D.y) <= tolerance.distance)

            let original3D = try curve3D.point(at: parameter, tolerance: tolerance)
            let result3D = try trimmed3D.point(at: parameter, tolerance: tolerance)
            #expect(original3D.isApproximatelyEqual(to: result3D, tolerance: tolerance.distance))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nonClampedNaturalDomainUsesTheCanonicalExactTrimPath() throws {
        let knots = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        let weights = [1.0, 0.8, 1.2, 1.0]
        let points2D = [
            Point2D(x: 0.0, y: 0.0),
            Point2D(x: 1.0, y: 0.4),
            Point2D(x: 2.0, y: -0.2),
            Point2D(x: 3.0, y: 0.3),
        ]
        let curve2D = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: points2D,
            weights: weights
        )
        let curve3D = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: points2D.map { Point3D(x: $0.x, y: $0.y, z: $0.x * 0.25) },
            weights: weights
        )
        try curve2D.validate(tolerance: tolerance)
        try curve3D.validate(tolerance: tolerance)
        #expect(curve2D.domain == .closed(2.0, 4.0))
        #expect(curve3D.domain == .closed(2.0, 4.0))

        let fullDomain2D = try curve2D.trimmed(
            from: 2.0,
            to: 4.0,
            tolerance: tolerance
        )
        let fullDomain3D = try curve3D.trimmed(
            from: 2.0,
            to: 4.0,
            tolerance: tolerance
        )
        #expect(fullDomain2D == curve2D)
        #expect(fullDomain3D == curve3D)

        for bounds in [(2.0, 4.0), (2.2, 3.8)] {
            let trimmed2D = try curve2D.trimmed(
                from: bounds.0,
                to: bounds.1,
                tolerance: tolerance
            )
            let trimmed3D = try curve3D.trimmed(
                from: bounds.0,
                to: bounds.1,
                tolerance: tolerance
            )
            for index in 0...8 {
                let parameter = bounds.0 + (bounds.1 - bounds.0) * Double(index) / 8.0
                let source2D = try curve2D.point(at: parameter, tolerance: tolerance)
                let result2D = try trimmed2D.point(at: parameter, tolerance: tolerance)
                #expect(hypot(source2D.x - result2D.x, source2D.y - result2D.y) <= tolerance.distance)

                let source3D = try curve3D.point(at: parameter, tolerance: tolerance)
                let result3D = try trimmed3D.point(at: parameter, tolerance: tolerance)
                #expect(source3D.isApproximatelyEqual(to: result3D, tolerance: tolerance.distance))
            }
        }
    }
}
