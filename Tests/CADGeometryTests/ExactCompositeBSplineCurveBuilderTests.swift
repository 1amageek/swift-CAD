import CADCore
import CADGeometry
import Foundation
import Testing

struct ExactCompositeBSplineCurveBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func preservesConnectedMixedDegreeRationalSpans() throws {
        let line = BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ]
        )
        let arc = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
                Point3D(x: 2.0, y: 1.0, z: 0.0),
            ],
            weights: [1.0, sqrt(0.5), 1.0]
        )

        let composite = try ExactCompositeBSplineCurveBuilder().build(
            spans: [line, arc],
            tolerance: .standard
        )

        #expect(composite.degree == 2)
        #expect(composite.isRational)
        #expect(try composite.point(at: 0.0, tolerance: .standard)
            .isApproximatelyEqual(to: Point3D(x: 0.0, y: 0.0, z: 0.0), tolerance: 1.0e-12))
        #expect(try composite.point(at: 1.0, tolerance: .standard)
            .isApproximatelyEqual(to: Point3D(x: 2.0, y: 1.0, z: 0.0), tolerance: 1.0e-12))

        for source in [line, arc] {
            for parameter in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let point = try source.point(at: parameter, tolerance: .standard)
                let projection = try Curve3D.bSpline(composite).parameterProjection(
                    of: point,
                    tolerance: .standard
                )
                #expect(projection.residual <= ModelingTolerance.standard.distance)
            }
        }
        try composite.validate(tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsDisconnectedSpans() throws {
        let first = line(from: .origin, to: Point3D(x: 1.0, y: 0.0, z: 0.0))
        let second = line(
            from: Point3D(x: 2.0, y: 0.0, z: 0.0),
            to: Point3D(x: 3.0, y: 0.0, z: 0.0)
        )

        #expect(throws: KernelError.self) {
            _ = try ExactCompositeBSplineCurveBuilder().build(
                spans: [first, second],
                tolerance: .standard
            )
        }
    }

    private func line(from start: Point3D, to end: Point3D) -> BSplineCurve3D {
        BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [start, end]
        )
    }
}
