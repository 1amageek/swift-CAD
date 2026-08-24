import CADCore
@testable import CADGeometry
import Testing

@Suite("Certified general implicit third-order derivatives", .serialized)
struct CertifiedGeneralImplicitThirdOrderDerivativeTests {
    private let tolerance = ModelingTolerance.standard
    private let intersector = DefaultSurfaceSurfaceIntersector()

    @Test(.timeLimit(.minutes(5)))
    func torusCylinderMatchesIndependentSecondDerivativeDifference() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let cylinderAxis = try Vector3D(x: 0.08, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: cylinderAxis,
            radius: 3.0
        ))
        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )
        let curves: [CertifiedGeneralTorusCylinderIntersectionCurve] =
            intersections.compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .generalTorusCylinder(curve) = exact.definition else {
                return nil
            }
            return curve
        }
        let curve = try #require(curves.first)

        try expectThirdDerivativeMatchesSecondDerivativeDifference(
            at: 0.37,
            thirdDerivative: {
                try curve.thirdDerivative(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                )
            },
            secondDerivative: {
                try curve.differential(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                ).secondDerivative
            },
            absoluteAccuracy: 2.0e-5,
            relativeAccuracy: 1.0e-7
        )
    }

    @Test(.timeLimit(.minutes(5)))
    func torusTorusMatchesIndependentSecondDerivativeDifference() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let secondAxis = try Vector3D(x: 0.25, y: 0.1, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let second = Surface3D.analytic(.torus(
            center: Point3D(x: 1.2, y: 0.2, z: 0.5),
            axis: secondAxis,
            majorRadius: 3.4,
            minorRadius: 0.7
        ))
        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let curves: [CertifiedGeneralTorusTorusIntersectionCurve] =
            intersections.compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .generalTorusTorus(curve) = exact.definition else {
                return nil
            }
            return curve
        }
        let curve = try #require(curves.first)

        try expectThirdDerivativeMatchesSecondDerivativeDifference(
            at: 0.31,
            thirdDerivative: {
                try curve.thirdDerivative(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                )
            },
            secondDerivative: {
                try curve.differential(
                    atNormalizedFraction: $0,
                    tolerance: tolerance
                ).secondDerivative
            },
            absoluteAccuracy: 2.0e-5,
            relativeAccuracy: 1.0e-7
        )
    }

    private func expectThirdDerivativeMatchesSecondDerivativeDifference(
        at fraction: Double,
        thirdDerivative: (Double) throws -> Vector3D,
        secondDerivative: (Double) throws -> Vector3D,
        absoluteAccuracy: Double,
        relativeAccuracy: Double
    ) throws {
        let step = 1.0e-5
        let actual = try thirdDerivative(fraction)
        let lower = try secondDerivative(fraction - step)
        let upper = try secondDerivative(fraction + step)
        let oracle = (upper - lower) / (2.0 * step)

        let scale = max(actual.length, oracle.length, 1.0)
        let accuracy = max(absoluteAccuracy, relativeAccuracy * scale)
        #expect(
            (actual - oracle).length <= accuracy,
            "actual magnitude: \(actual.length), oracle magnitude: \(oracle.length)"
        )
    }
}
