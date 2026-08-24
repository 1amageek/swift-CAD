import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedCylinderCylinderSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-7,
        angle: 1.0e-8,
        relative: 1.0e-9
    )

    @Test(.timeLimit(.minutes(3)))
    func thirdDerivativesCoverFullAndEndpointRegularizedBranches() throws {
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
        var curves = try [
            CertifiedCylinderCylinderIntersectionCurve.ComponentKind
                .negativeFullBranch,
            .positiveFullBranch,
        ].map { componentKind in
            try CertifiedCylinderCylinderIntersectionCurve(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                componentKind: componentKind,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                tolerance: tolerance
            )
        }

        let first = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.25, y: -0.5, z: 0.0),
            axis: .unitZ,
            radius: 2.25
        ))
        let second = Surface3D.analytic(.cylinder(
            origin: Point3D(x: -0.5, y: 0.75, z: 1.0),
            axis: try Vector3D(
                x: 1.0,
                y: 0.25,
                z: 0.1
            ).normalized(tolerance: tolerance.distance),
            radius: 1.5
        ))
        let bounded: [CertifiedCylinderCylinderIntersectionCurve] = try
            DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            options: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 20
            ),
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .cylinderCylinder(curve) = exact.definition,
                  curve.componentKind == .boundedAngularInterval else {
                return nil
            }
            return curve
        }
        #expect(bounded.isEmpty == false)
        curves.append(contentsOf: bounded)

        for curve in curves {
            let bounds = try curve.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            let third = try #require(bounds.third)
            for fraction in [0.0, 0.23, 0.57, 1.0] {
                let actual = try curve.thirdDerivative(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                #expect(actual.length <= third)
                let oracle = try secondDerivativeDifference(
                    curve: curve,
                    at: fraction
                )
                let scale = max(actual.length, oracle.length, 1.0)
                #expect(
                    (actual - oracle).length
                        <= max(3.0e-4, scale * 2.0e-6),
                    "component: \(curve.componentKind), fraction: \(fraction), magnitude: \(scale)"
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func fullBranchBoundsEncloseTrimmedSpatialDifferentials() throws {
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
        let componentKinds:
            [CertifiedCylinderCylinderIntersectionCurve.ComponentKind] = [
                .negativeFullBranch,
                .positiveFullBranch,
            ]
        let trims: [(start: Double, end: Double)] = [
            (start: 0.15, end: 0.85),
            (start: 0.85, end: 0.15),
        ]
        for componentKind in componentKinds {
            let source = try CertifiedCylinderCylinderIntersectionCurve(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                componentKind: componentKind,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                tolerance: tolerance
            )
            let sourceBounds = try source
                .fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            let sourceThird = try #require(sourceBounds.third)
            let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
                cylinderCylinderCurve: source,
                firstSurface: parameterizedSurface,
                secondSurface: referenceSurface,
                tolerance: tolerance
            )
            for trim in trims {
                let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                    intersection: truth,
                    role: .first,
                    startFraction: trim.start,
                    endFraction: trim.end,
                    tolerance: tolerance
                )
                let pcurveBounds = try pcurve
                    .fullBranchCylinderSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
                let scale = pcurve.endFraction - pcurve.startFraction
                #expect(
                    pcurveBounds.first
                        >= sourceBounds.first * abs(scale)
                )
                #expect(
                    pcurveBounds.second
                        >= sourceBounds.second * scale * scale
                )
                let third = try #require(pcurveBounds.third)
                #expect(
                    third
                        >= sourceThird * abs(scale) * abs(scale) * abs(scale)
                )

                let lift = SurfaceLiftCurve3D(
                    surface: parameterizedSurface,
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                )
                let curve = Curve3D.surfaceLift(lift)
                let interval = try ScalarInterval(lower: 0.2, upper: 0.8)
                let optionalCertifiedSecond =
                    try SurfaceLiftDifferentialBounder()
                        .secondDerivativeMagnitude(
                            lift: lift,
                            interval: interval,
                            tolerance: tolerance
                        )
                let certifiedSecond = try #require(
                    optionalCertifiedSecond
                )
                for index in 0...128 {
                    let fraction = interval.lower
                        + interval.width * Double(index) / 128.0
                    let geometry = try curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    #expect(
                        geometry.firstDerivative.length
                            <= pcurveBounds.first
                    )
                    #expect(
                        geometry.secondDerivative.length
                            <= pcurveBounds.second
                    )
                    #expect(
                        geometry.secondDerivative.length
                            <= certifiedSecond
                    )
                    let thirdDerivative = try curve
                        .parameterDerivativesThroughThirdOrder(
                            at: fraction,
                            tolerance: tolerance
                        ).thirdDerivative
                    #expect(thirdDerivative.length <= third)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedBranchBoundsEncloseEndpointRegularizedDifferentials() throws {
        let tolerance = ModelingTolerance.standard
        let first = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.25, y: -0.5, z: 0.0),
            axis: .unitZ,
            radius: 2.25
        ))
        let second = Surface3D.analytic(.cylinder(
            origin: Point3D(x: -0.5, y: 0.75, z: 1.0),
            axis: try Vector3D(
                x: 1.0,
                y: 0.25,
                z: 0.1
            ).normalized(tolerance: tolerance.distance),
            radius: 1.5
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector()
            .intersections(
                first: first,
                second: second,
                options: SurfaceSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 20
                ),
                tolerance: tolerance
            )
        let exactCurves: [CertifiedAnalyticAnalyticIntersectionCurve] =
            intersections.compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .cylinderCylinder(curve) = exact.definition,
                  curve.componentKind == .boundedAngularInterval else {
                return nil
            }
            return exact
        }
        #expect(exactCurves.isEmpty == false)

        for exact in exactCurves {
            let source = try #require(exact.cylinderCylinderCurve)
            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.0, end: 0.01),
                (start: 0.1, end: 0.9),
                (start: 0.9, end: 0.1),
                (start: 0.8984375, end: 0.90234375),
                (start: 0.99, end: 1.0),
            ] {
                let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                    intersection: exact,
                    role: .first,
                    startFraction: trim.start,
                    endFraction: trim.end,
                    tolerance: tolerance
                )
                let bounds = try pcurve
                    .cylinderSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
                let scale = abs(trim.end - trim.start)
                let sourceBounds = try source
                    .spatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(
                            trim.start,
                            trim.end
                        ),
                        toNormalizedFraction: max(
                            trim.start,
                            trim.end
                        ),
                        tolerance: tolerance
                    )
                #expect(bounds.first >= sourceBounds.first * scale)
                #expect(
                    bounds.second
                        >= sourceBounds.second * scale * scale
                )
                let sourceThird = try #require(sourceBounds.third)
                let third = try #require(bounds.third)
                #expect(third >= sourceThird * scale * scale * scale)
                let surface = exact.surface(for: .first)
                let lift = SurfaceLiftCurve3D(
                    surface: surface,
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                )
                let curve = Curve3D.surfaceLift(lift)
                let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
                let certifiedSecond = try #require(
                    try SurfaceLiftDifferentialBounder()
                        .secondDerivativeMagnitude(
                            lift: lift,
                            interval: interval,
                            tolerance: tolerance
                        )
                )
                for fraction in [
                    0.0, 1.0e-8, 1.0e-6, 0.001, 0.25,
                    0.5, 0.75, 0.999, 1.0 - 1.0e-6,
                    1.0 - 1.0e-8, 1.0,
                ] {
                    let geometry = try curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    for surfaceRole in [
                        SurfaceIntersectionSurfaceRole.first,
                        .second,
                    ] {
                        let projection = try exact.surface(
                            for: surfaceRole
                        ).parameterProjection(
                            of: geometry.position,
                            tolerance: tolerance
                        )
                        #expect(
                            projection.residual
                                <= exact.maximumResidualUpperBound
                        )
                    }
                    #expect(geometry.firstDerivative.length <= bounds.first)
                    #expect(geometry.secondDerivative.length <= bounds.second)
                    #expect(
                        geometry.secondDerivative.length
                            <= certifiedSecond
                    )
                    let thirdDerivative = try curve
                        .parameterDerivativesThroughThirdOrder(
                            at: fraction,
                            tolerance: tolerance
                        ).thirdDerivative
                    #expect(thirdDerivative.length <= third)
                }
            }
        }
    }

    private func secondDerivativeDifference(
        curve: CertifiedCylinderCylinderIntersectionCurve,
        at fraction: Double
    ) throws -> Vector3D {
        let endpointStep = 2.0e-4
        func second(_ value: Double) throws -> Vector3D {
            try curve.differential(
                atNormalizedFraction: value,
                tolerance: tolerance
            ).secondDerivative
        }
        if fraction == 0.0 {
            let step = endpointStep
            return (
                try second(0.0) * -25.0
                    + second(step) * 48.0
                    - second(2.0 * step) * 36.0
                    + second(3.0 * step) * 16.0
                    - second(4.0 * step) * 3.0
            ) / (12.0 * step)
        }
        if fraction == 1.0 {
            let step = endpointStep
            return (
                try second(1.0) * 25.0
                    - second(1.0 - step) * 48.0
                    + second(1.0 - 2.0 * step) * 36.0
                    - second(1.0 - 3.0 * step) * 16.0
                    + second(1.0 - 4.0 * step) * 3.0
            ) / (12.0 * step)
        }
        let interiorStep = 1.0e-5
        return (
            try second(fraction + interiorStep)
                - second(fraction - interiorStep)
        ) / (2.0 * interiorStep)
    }
}
