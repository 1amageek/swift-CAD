import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("Certified Curve Directional Parameter Projection")
struct CurveDirectionalParameterProjectionTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func raySelectsNearestForwardIntersection() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -2.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: -2.0, z: 0.0),
                Point3D(x: 2.0, y: 1.0, z: 0.0),
            ]
        ))

        let projection = try curve.directionalParameterProjection(
            from: Point3D(x: 0.8, y: 0.0, z: 0.0),
            along: Vector3D.unitX,
            options: CurveDirectionalParameterProjectionOptions(range: .ray),
            tolerance: tolerance
        )

        let expectedParameter = (3.0 + sqrt(3.0)) / 6.0
        #expect(abs(projection.parameter - expectedParameter) <= 1.0e-8)
        #expect(projection.signedDistanceAlongDirection > 0.0)
        #expect(projection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonIntersectingLineReturnsTypedEmptyResult() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -2.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: -2.0, z: 0.0),
                Point3D(x: 2.0, y: 1.0, z: 0.0),
            ]
        ))

        do {
            _ = try curve.directionalParameterProjection(
                from: Point3D(x: 0.0, y: 2.0, z: 0.0),
                along: Vector3D.unitX,
                options: CurveDirectionalParameterProjectionOptions(),
                tolerance: tolerance
            )
            Issue.record("A non-intersecting line must not produce a projection result.")
        } catch let error as KernelError {
            #expect(error.code == .emptyResult)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func curveCoincidentWithProjectionLineUsesCertifiedClosestPoint() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ]
        ))

        let projection = try curve.directionalParameterProjection(
            from: .origin,
            along: Vector3D.unitX,
            options: CurveDirectionalParameterProjectionOptions(),
            tolerance: tolerance
        )

        #expect(abs(projection.parameter - 0.5) <= tolerance.angle)
        #expect(projection.point.isApproximatelyEqual(
            to: .origin,
            tolerance: tolerance.distance
        ))
        #expect(projection.residual <= tolerance.distance)
    }
}
