import Foundation
import Testing
import CADCore
@testable import CADGeometry

@Suite("Exact surface-lift curves")
struct SurfaceLiftCurve3DTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-10,
        angle: 1.0e-11
    )

    @Test(.timeLimit(.minutes(1)))
    func evaluatesPositionAndTwoDerivativesByExactChainRule() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 1.0)],
            ]
        )
        let parameterCurve = SurfaceParameterCurve.affine(
            origin: Point2D(x: 0.0, y: 0.0),
            direction: Point2D(x: 1.0, y: 0.5),
            startParameter: 0.0,
            endParameter: 1.0
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: .bSpline(surface),
            parameterCurve: parameterCurve
        ))

        let differential = try curve.differentialGeometry(
            at: 0.4,
            tolerance: tolerance
        )

        #expect(differential.position.isApproximatelyEqual(
            to: Point3D(x: 0.4, y: 0.2, z: 0.08),
            tolerance: tolerance.distance
        ))
        #expect((differential.firstDerivative - Vector3D(x: 1.0, y: 0.5, z: 0.4)).length
            <= tolerance.distance)
        #expect((differential.secondDerivative - Vector3D(x: 0.0, y: 0.0, z: 1.0)).length
            <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func curveAndNestedLiftUseStrictCurrentSchema() throws {
        let lift = SurfaceLiftCurve3D(
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            parameterCurve: .affine(
                origin: Point2D(x: 0.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 1.0),
                startParameter: 0.0,
                endParameter: 1.0
            )
        )
        let curve = Curve3D.surfaceLift(lift)
        let data = try JSONEncoder().encode(curve)
        #expect(try JSONDecoder().decode(Curve3D.self, from: data) == curve)

        var curveObject = try encodedObject(curve)
        curveObject["legacyApproximationTolerance"] = 1.0e-4
        try expectDecodingFailure(Curve3D.self, from: curveObject)

        var liftObject = try encodedObject(lift)
        liftObject["sampledPolyline"] = [[0.0, 0.0, 0.0]]
        try expectDecodingFailure(SurfaceLiftCurve3D.self, from: liftObject)
    }

    private func encodedObject<Value: Encodable>(_ value: Value) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SurfaceLiftCurveTestError.expectedObject
        }
        return object
    }

    private func expectDecodingFailure<Value: Decodable>(
        _ type: Value.Type,
        from object: [String: Any]
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(type, from: data)
        }
    }
}

private enum SurfaceLiftCurveTestError: Error {
    case expectedObject
}
