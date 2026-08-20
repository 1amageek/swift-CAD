import Foundation
import Testing
import CADCore
import CADGeometry
import CADModeling

@Suite("Evaluated curve validation")
struct EvaluatedCurveValidationTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-8,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func exactPointParametersValidateAnAmbiguousSelfOverlapWithoutInverseProjection() throws {
        let curve = try selfOverlappingCurve(
            points: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
            ]
        )

        try curve.validate(tolerance: tolerance)
        let decoded = try JSONDecoder().decode(
            EvaluatedCurve.self,
            from: JSONEncoder().encode(curve)
        )
        #expect(decoded == curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactPointParametersRejectMismatchedDisplayGeometry() throws {
        let curve = try selfOverlappingCurve(
            points: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.001, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
            ]
        )

        do {
            try curve.validate(tolerance: tolerance)
            Issue.record("A display point that disagrees with its exact parameter must fail validation.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
            #expect(abs((error.residual ?? 0.0) - 0.001) <= tolerance.distance)
        }
    }

    private func selfOverlappingCurve(points: [Point3D]) throws -> EvaluatedCurve {
        let exactCurve = BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 0.25, 0.5, 0.75, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
            ]
        )
        try exactCurve.validate(tolerance: tolerance)
        return EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .spline,
            points: points,
            isClosed: true,
            plane: .xy,
            exactCurve: .bSpline(exactCurve),
            exactParameterDomain: exactCurve.domain,
            exactPointParameters: [0.0, 0.25, 0.5, 0.75, 1.0]
        )
    }
}
