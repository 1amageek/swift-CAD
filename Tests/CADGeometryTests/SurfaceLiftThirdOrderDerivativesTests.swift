import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Surface-lift third-order derivatives")
struct SurfaceLiftThirdOrderDerivativesTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10,
        relative: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func sphericalGreatCircleMatchesIndependentSecondDerivativeDifference() throws {
        let inverseSquareRootTwo = sqrt(0.5)
        let lift = SurfaceLiftCurve3D(
            surface: .analytic(.sphere(center: .origin, radius: 2.3)),
            parameterCurve: .sphericalGreatCircle(
                cosine: .unitY,
                sine: Vector3D(
                    x: inverseSquareRootTwo,
                    y: 0.0,
                    z: inverseSquareRootTwo
                ),
                startParameter: 0.2,
                endParameter: 0.9
            )
        )

        try expectThirdDerivativeMatchesSecondDerivativeDifference(
            of: lift,
            at: 0.43,
            accuracy: 2.0e-7
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func projectedParabolaMatchesIndependentSecondDerivativeDifference() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let lift = SurfaceLiftCurve3D(
            surface: plane,
            parameterCurve: .projectedAnalytic(
                try ProjectedAnalyticSurfaceParameterCurve(
                    curve: .analytic(.parabola(Parabola3D(
                        vertex: .origin,
                        normal: .unitZ,
                        axis: .unitX,
                        focalLength: 0.5
                    ))),
                    surface: plane,
                    startParameter: -0.8,
                    endParameter: 1.1,
                    tolerance: tolerance
                )
            )
        )

        try expectThirdDerivativeMatchesSecondDerivativeDifference(
            of: lift,
            at: 0.37,
            accuracy: 2.0e-7
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rigidImageMatchesIndependentSecondDerivativeDifference() throws {
        let sourceSurface = Surface3D.analytic(.sphere(
            center: Point3D(x: -0.2, y: 0.1, z: 0.3),
            radius: 1.7
        ))
        let source = SurfaceLiftCurve3D(
            surface: sourceSurface,
            parameterCurve: .harmonic(
                center: Point2D(x: 0.5, y: 0.1),
                cosine: Point2D(x: 0.4, y: 0.08),
                sine: Point2D(x: -0.06, y: 0.12),
                startParameter: 0.15,
                endParameter: 1.35
            )
        )
        let transform = try RigidTransform3D.rotated(
            around: Point3D(x: 0.1, y: -0.3, z: 0.2),
            direction: Vector3D(x: 1.0, y: -1.5, z: 2.0),
            angle: 0.71,
            tolerance: tolerance
        )
        let targetSurface = try transform.applying(
            to: sourceSurface,
            tolerance: tolerance
        )
        let lift = SurfaceLiftCurve3D(
            surface: targetSurface,
            parameterCurve: .rigidImage(
                try RigidImageSurfaceParameterCurve(
                    source: source,
                    targetSurface: targetSurface,
                    transform: transform,
                    startFraction: 0.08,
                    endFraction: 0.91,
                    tolerance: tolerance
                )
            )
        )

        try expectThirdDerivativeMatchesSecondDerivativeDifference(
            of: lift,
            at: 0.58,
            accuracy: 3.0e-6
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func certifiedAnalyticPairTraversesTrimmedAndReversedSurfaceLiftPath() throws {
        let tolerance = ModelingTolerance.standard
        let parameterizedSurface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitY,
            radius: 1.0
        ))
        let referenceSurface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: try Vector3D(
                x: 0.0,
                y: 1.0,
                z: 1.0
            ).normalized(tolerance: tolerance.distance),
            radius: 4.0
        ))
        let owner = try CertifiedCylinderCylinderIntersectionCurve(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
            componentKind: .negativeFullBranch,
            lowerAngle: 0.0,
            upperAngle: 2.0 * Double.pi,
            tolerance: tolerance
        )
        let intersection = try CertifiedAnalyticAnalyticIntersectionCurve(
            cylinderCylinderCurve: owner,
            firstSurface: parameterizedSurface,
            secondSurface: referenceSurface,
            tolerance: tolerance
        )

        for (role, start, end) in [
            (SurfaceIntersectionSurfaceRole.first, 0.17, 0.83),
            (.second, 0.83, 0.17),
        ] {
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: intersection,
                role: role,
                startFraction: start,
                endFraction: end,
                tolerance: tolerance
            )
            let lift = SurfaceLiftCurve3D(
                surface: intersection.surface(for: role),
                parameterCurve: .certifiedAnalyticPair(pcurve)
            )
            try expectThirdDerivativeMatchesSecondDerivativeDifference(
                of: lift,
                at: 0.41,
                accuracy: 2.0e-5,
                tolerance: tolerance
            )
        }
    }

    private func expectThirdDerivativeMatchesSecondDerivativeDifference(
        of lift: SurfaceLiftCurve3D,
        at fraction: Double,
        accuracy: Double,
        tolerance: ModelingTolerance? = nil
    ) throws {
        let step = 1.0e-5
        let curve = Curve3D.surfaceLift(lift)
        let tolerance = tolerance ?? self.tolerance
        let actual = try curve.parameterDerivativesThroughThirdOrder(
            at: fraction,
            tolerance: tolerance
        ).thirdDerivative
        let lower = try curve.differentialGeometry(
            at: fraction - step,
            tolerance: tolerance
        ).secondDerivative
        let upper = try curve.differentialGeometry(
            at: fraction + step,
            tolerance: tolerance
        ).secondDerivative
        let oracle = (upper - lower) / (2.0 * step)

        #expect((actual - oracle).length <= accuracy)
    }
}
