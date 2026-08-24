import CADCore
@testable import CADGeometry
import Testing

@Suite("Validated curve evaluation")
struct ValidatedCurve3DTests {
    @Test(.timeLimit(.minutes(1)))
    func retainsOneValidationBoundaryAcrossRepeatedEvaluation() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                ],
            ]
        )
        let source = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: .bSpline(surface),
            parameterCurve: .affine(
                origin: Point2D(x: 0.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 0.5),
                startParameter: 0.0,
                endParameter: 1.0
            )
        ))
        let validated = try ValidatedCurve3D(
            source,
            tolerance: .standard
        )

        for index in 0...32 {
            let parameter = Double(index) / 32.0
            let differential = try validated.differentialGeometry(at: parameter)
            #expect(differential.position.isApproximatelyEqual(
                to: try validated.point(at: parameter),
                tolerance: ModelingTolerance.standard.distance
            ))
        }

        let projectedSource = try validated.point(at: 0.375)
        let projection = try validated.parameterProjection(
            of: projectedSource,
            options: CurveParameterProjectionOptions(
                parameterRange: try ScalarInterval(lower: 0.0, upper: 1.0)
            )
        )
        #expect(abs(projection.parameter - 0.375) <= 1.0e-7)
        #expect(projection.residual <= ModelingTolerance.standard.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsInvalidCurveBeforeEvaluation() {
        let invalid = Curve3D.bSpline(BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [.origin, Point3D(x: 1.0, y: 0.0, z: 0.0)]
        ))

        #expect(throws: GeometryError.self) {
            try ValidatedCurve3D(invalid, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesTheValidatedClosedParameterDomain() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [2.0, 2.0, 5.0, 5.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 3.0, y: 1.0, z: -1.0),
            ]
        ))
        let validated = try ValidatedCurve3D(curve, tolerance: .standard)

        #expect(validated.parameterDomain == .closed(2.0, 5.0))
        #expect(throws: GeometryError.self) {
            try validated.point(at: 1.0)
        }
        #expect(throws: GeometryError.self) {
            try validated.differentialGeometry(at: 6.0)
        }
    }
}
