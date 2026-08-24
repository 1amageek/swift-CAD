import CADCore
@testable import CADGeometry
import Testing

struct CertifiedSphereTorusSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(3)))
    func thirdDerivativesCoverRootFreeAndRegularizedComponents() throws {
        let rootFree = try rootFreeCurves()
        let bounded = try boundedCurves()
        let open = try poleSplitOpenCurves()
        #expect(rootFree.count == 2)
        #expect(bounded.isEmpty == false)
        #expect(open.count == 3)
        for exact in rootFree + bounded + open {
            guard case let .sphereTorus(curve) = exact.definition else {
                Issue.record("Expected a certified sphere-torus curve.")
                continue
            }
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
                        <= max(5.0e-4, scale * 3.0e-6),
                    "component: \(curve.componentKind), fraction: \(fraction), magnitude: \(scale)"
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func rootFreeBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try rootFreeCurves()
        #expect(exactCurves.count == 2)
        let componentKinds:
            Set<CertifiedSphereTorusIntersectionCurve.ComponentKind> =
                Set(exactCurves.compactMap { exact in
                    guard case let .sphereTorus(curve) = exact.definition else {
                        return nil
                    }
                    return curve.componentKind
                })
        let expectedKinds:
            Set<CertifiedSphereTorusIntersectionCurve.ComponentKind> = [
            .negativeFullBranch,
            .positiveFullBranch,
        ]
        #expect(componentKinds == expectedKinds)

        for exact in exactCurves {
            guard case let .sphereTorus(source) = exact.definition else {
                Issue.record("Expected a certified sphere-torus curve.")
                continue
            }
            let sourceBounds = try source
                .fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            #expect(sourceBounds.first.isFinite)
            #expect(sourceBounds.second.isFinite)
            let sourceThird = try #require(sourceBounds.third)
            #expect(sourceThird.isFinite)
            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.1, end: 0.7),
                (start: 0.8, end: 0.2),
            ] {
                let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                    intersection: exact,
                    role: .first,
                    startFraction: trim.start,
                    endFraction: trim.end,
                    tolerance: tolerance
                )
                let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
                #expect(bounds.first.isFinite)
                #expect(bounds.second.isFinite)
                #expect(bounds.first > 0.0)
                #expect(bounds.second > 0.0)
                let third = try #require(bounds.third)
                let scale = abs(trim.end - trim.start)
                let localSourceBounds = try source
                    .spatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(trim.start, trim.end),
                        toNormalizedFraction: max(trim.start, trim.end),
                        tolerance: tolerance
                    )
                let localSourceThird = try #require(localSourceBounds.third)
                #expect(bounds.first >= localSourceBounds.first * scale)
                #expect(
                    bounds.second
                        >= localSourceBounds.second * scale * scale
                )
                #expect(
                    third
                        >= localSourceThird * scale * scale * scale
                )

                let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                    surface: exact.surface(for: .first),
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                ))
                for index in 0...128 {
                    let fraction = Double(index) / 128.0
                    let geometry = try curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    #expect(geometry.firstDerivative.length <= bounds.first)
                    #expect(geometry.secondDerivative.length <= bounds.second)
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

    @Test(.timeLimit(.minutes(2)))
    func rootFreeBranchIntersectsLocalTransverseAndTangentPlanes() throws {
        let exact = try #require(try rootFreeCurves().first {
            guard case let .sphereTorus(curve) = $0.definition else {
                return false
            }
            return curve.componentKind == .positiveFullBranch
        })
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            tolerance: tolerance
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: exact.surface(for: .first),
            parameterCurve: .certifiedAnalyticPair(pcurve)
        ))
        let geometry = try curve.differentialGeometry(
            at: 0.5,
            tolerance: tolerance
        )
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(lower: 0.499, upper: 0.501),
            maximumSubdivisionDepth: 24
        )
        let transversePlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: try geometry.firstDerivative.normalized(
                tolerance: tolerance.distance
            )
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: options,
            tolerance: tolerance
        )
        #expect(transverse.count == 1)
        #expect(transverse.first?.kind == .transverse)

        let tangentSquared = geometry.firstDerivative.dot(
            geometry.firstDerivative
        )
        let normalCurvature = geometry.secondDerivative
            - geometry.firstDerivative * (
                geometry.secondDerivative.dot(geometry.firstDerivative)
                    / tangentSquared
            )
        let tangentPlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: try normalCurvature.normalized(
                tolerance: tolerance.distance
            )
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentPlane,
            options: options,
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        #expect(tangent.first?.kind == .tangent)
    }

    @Test(.timeLimit(.minutes(1)))
    func subToleranceRootCellUsesContainingDifferentialCertificate() throws {
        let exact = try #require(try rootFreeCurves().first)
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            tolerance: tolerance
        )
        let lift = SurfaceLiftCurve3D(
            surface: exact.surface(for: .first),
            parameterCurve: .certifiedAnalyticPair(pcurve)
        )
        let lower = 0.5
        let upper = lower + tolerance.relative * 0.5
        let interval = try ScalarInterval(lower: lower, upper: upper)
        let bound = try #require(
            try SurfaceLiftDifferentialBounder().secondDerivativeMagnitude(
                lift: lift,
                interval: interval,
                tolerance: tolerance
            )
        )
        let geometry = try lift.differentialGeometry(
            atNormalizedFraction: interval.midpoint,
            tolerance: tolerance
        )
        #expect(bound.isFinite)
        #expect(geometry.secondDerivative.length <= bound)
    }

    @Test(.timeLimit(.minutes(1)))
    func endpointRegularizedComponentEnclosesSpatialDifferentials() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.5, y: 0.0, z: 0.0),
            radius: 2.0
        ))
        let exactCurves:
            [CertifiedAnalyticAnalyticIntersectionCurve] =
                try DefaultSurfaceSurfaceIntersector().intersections(
                    first: sphere,
                    second: torus,
                    tolerance: tolerance
                ).compactMap {
                    intersection
                        -> CertifiedAnalyticAnalyticIntersectionCurve? in
                    guard case let .curve(result) = intersection,
                          case let .analyticAnalytic(exact) = result.truth,
                          case let .sphereTorus(curve) = exact.definition,
                          curve.componentKind == .boundedAngularInterval else {
                        return nil
                    }
                    return exact
                }
        let exact = try #require(exactCurves.first)
        for trim in [
            (start: 0.0, end: 1.0),
            (start: 0.03, end: 0.47),
            (start: 0.91, end: 0.08),
        ] {
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: .first,
                startFraction: trim.start,
                endFraction: trim.end,
                tolerance: tolerance
            )
            #expect(pcurve.hasSpatialDifferentialMagnitudeBounds)
            let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            #expect(bounds.first.isFinite)
            #expect(bounds.second.isFinite)
            let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                surface: exact.surface(for: .first),
                parameterCurve: .certifiedAnalyticPair(pcurve)
            ))
            for index in 0...256 {
                let fraction = Double(index) / 256.0
                let geometry = try curve.differentialGeometry(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect(geometry.firstDerivative.length <= bounds.first)
                #expect(geometry.secondDerivative.length <= bounds.second)
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func poleSplitOpenComponentsEncloseSpatialDifferentials() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 4.0, y: 0.0, z: -1.0),
            radius: 1.0
        ))
        let exactCurves:
            [CertifiedAnalyticAnalyticIntersectionCurve] =
                try DefaultSurfaceSurfaceIntersector().intersections(
                    first: sphere,
                    second: torus,
                    tolerance: tolerance
                ).compactMap {
                    intersection
                        -> CertifiedAnalyticAnalyticIntersectionCurve? in
                    guard case let .curve(result) = intersection,
                          case let .analyticAnalytic(exact) = result.truth,
                          case let .sphereTorus(curve) = exact.definition,
                          curve.componentKind == .negativeOpenAngularInterval
                            || curve.componentKind
                                == .positiveOpenAngularInterval else {
                        return nil
                    }
                    return exact
                }
        #expect(exactCurves.count == 3)
        for exact in exactCurves {
            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.02, end: 0.53),
                (start: 0.94, end: 0.07),
            ] {
                let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                    intersection: exact,
                    role: .first,
                    startFraction: trim.start,
                    endFraction: trim.end,
                    tolerance: tolerance
                )
                #expect(pcurve.hasSpatialDifferentialMagnitudeBounds)
                let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
                let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                    surface: exact.surface(for: .first),
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                ))
                for index in 0...128 {
                    let fraction = Double(index) / 128.0
                    let geometry = try curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    #expect(
                        geometry.firstDerivative.length <= bounds.first
                    )
                    #expect(
                        geometry.secondDerivative.length <= bounds.second
                    )
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func boundedComponentIntersectsLocalPlanes() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let boundedSphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.5, y: 0.0, z: 0.0),
            radius: 2.0
        ))
        let bounded = try #require(
            try DefaultSurfaceSurfaceIntersector().intersections(
                first: boundedSphere,
                second: torus,
                tolerance: tolerance
            ).compactMap { intersection
                -> CertifiedAnalyticAnalyticIntersectionCurve? in
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .sphereTorus(curve) = exact.definition,
                      curve.componentKind == .boundedAngularInterval else {
                    return nil
                }
                return exact
            }.first
        )
        try assertLocalPlaneContacts(exact: bounded, fraction: 0.25)
    }

    @Test(.timeLimit(.minutes(2)))
    func poleSplitOpenComponentIntersectsLocalPlanes() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 4.0, y: 0.0, z: -1.0),
            radius: 1.0
        ))
        let open = try #require(
            try DefaultSurfaceSurfaceIntersector().intersections(
                first: sphere,
                second: torus,
                tolerance: tolerance
            ).compactMap { intersection
                -> CertifiedAnalyticAnalyticIntersectionCurve? in
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .sphereTorus(curve) = exact.definition,
                      curve.componentKind == .negativeOpenAngularInterval
                        || curve.componentKind
                            == .positiveOpenAngularInterval else {
                    return nil
                }
                return exact
            }.first
        )
        try assertLocalPlaneContacts(
            exact: open,
            fraction: 0.25,
            includesTangent: false
        )
    }

    private func assertLocalPlaneContacts(
        exact: CertifiedAnalyticAnalyticIntersectionCurve,
        fraction: Double,
        includesTangent: Bool = true
    ) throws {
        let sourceLower = fraction - 0.0001
        let sourceUpper = fraction + 0.0001
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            startFraction: sourceLower,
            endFraction: sourceUpper,
            tolerance: tolerance
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: exact.surface(for: .first),
            parameterCurve: .certifiedAnalyticPair(pcurve)
        ))
        let geometry = try curve.differentialGeometry(
            at: 0.5,
            tolerance: tolerance
        )
        let sourceGeometry = try exact.differential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(
                lower: 0.49,
                upper: 0.51
            ),
            maximumSubdivisionDepth: 20
        )
        let transversePlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: try sourceGeometry.firstDerivative.normalized(
                tolerance: tolerance.distance
            )
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: options,
            tolerance: tolerance
        )
        #expect(transverse.count == 1)
        #expect(transverse.first?.kind == .transverse)
        guard includesTangent else { return }

        let tangentSquared = sourceGeometry.firstDerivative.dot(
            sourceGeometry.firstDerivative
        )
        let normalCurvature = sourceGeometry.secondDerivative
            - sourceGeometry.firstDerivative * (
                sourceGeometry.secondDerivative.dot(
                    sourceGeometry.firstDerivative
                )
                    / tangentSquared
            )
        let tangentPlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: try normalCurvature.normalized(
                tolerance: tolerance.distance
            )
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentPlane,
            options: options,
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        #expect(tangent.first?.kind == .tangent)
    }

    private func rootFreeCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.5, y: 0.0, z: 0.25),
            radius: 3.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereTorus(curve) = exact.definition,
                  curve.componentKind == .negativeFullBranch
                    || curve.componentKind == .positiveFullBranch else {
                return nil
            }
            return exact
        }
    }

    private func boundedCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 0.5, y: 0.0, z: 0.0),
            radius: 2.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereTorus(curve) = exact.definition,
                  curve.componentKind == .boundedAngularInterval else {
                return nil
            }
            return exact
        }
    }

    private func poleSplitOpenCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let sphere = Surface3D.analytic(.sphere(
            center: Point3D(x: 4.0, y: 0.0, z: -1.0),
            radius: 1.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereTorus(curve) = exact.definition,
                  curve.componentKind == .negativeOpenAngularInterval
                    || curve.componentKind
                        == .positiveOpenAngularInterval else {
                return nil
            }
            return exact
        }
    }

    private func secondDerivativeDifference(
        curve: CertifiedSphereTorusIntersectionCurve,
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
