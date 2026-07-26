import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedSphereCylinderSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func rootFreeBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try rootFreeCurves()
        #expect(exactCurves.count == 2)
        let componentKinds:
            Set<CertifiedSphereCylinderIntersectionCurve.ComponentKind> =
                Set(exactCurves.compactMap { exact in
                    guard case let .sphereCylinder(curve) = exact.definition
                    else {
                        return nil
                    }
                    return curve.componentKind
                })
        let expectedKinds:
            Set<CertifiedSphereCylinderIntersectionCurve.ComponentKind> = [
            .negativeFullBranch,
            .positiveFullBranch,
        ]
        #expect(componentKinds == expectedKinds)
        for exact in exactCurves {
            guard case let .sphereCylinder(source) = exact.definition else {
                Issue.record("Expected a certified sphere-cylinder curve.")
                continue
            }
            let sourceBounds = try source
                .fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
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
                let scale = abs(trim.end - trim.start)
                #expect(bounds.first >= sourceBounds.first * scale)
                #expect(bounds.second >= sourceBounds.second * scale * scale)

                let lift = SurfaceLiftCurve3D(
                    surface: exact.surface(for: .first),
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                )
                let curve = Curve3D.surfaceLift(lift)
                let interval = try ScalarInterval(
                    lower: 0.15,
                    upper: 0.85
                )
                let certifiedSecond = try #require(
                    try SurfaceLiftDifferentialBounder()
                        .secondDerivativeMagnitude(
                            lift: lift,
                            interval: interval,
                            tolerance: tolerance
                        )
                )
                for index in 0...128 {
                    let fraction = Double(index) / 128.0
                    let geometry = try curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    #expect(geometry.firstDerivative.length <= bounds.first)
                    #expect(geometry.secondDerivative.length <= bounds.second)
                    if interval.contains(fraction) {
                        #expect(
                            geometry.secondDerivative.length <= certifiedSecond
                        )
                    }
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rootFreeBranchIntersectsThirdPlaneTransverselyAndTangentially() throws {
        let exact = try #require(try rootFreeCurves().first {
            guard case let .sphereCylinder(curve) = $0.definition else {
                return false
            }
            return curve.componentKind == .positiveFullBranch
        })
        let curve = exactCurve(exact)
        let transversePlane = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitY
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: .init(),
            tolerance: tolerance
        )
        #expect(transverse.count == 2)
        #expect(transverse.allSatisfy {
            $0.kind == .transverse
                && abs($0.point.y) <= tolerance.distance
        })
        let rangeExcluded = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: transversePlane,
                options: CurveSurfaceIntersectionOptions(
                    curveRange: try ScalarInterval(
                        lower: 0.3,
                        upper: 0.7
                    )
                ),
                tolerance: tolerance
            )
        #expect(rangeExcluded.isEmpty)

        let tangentPoint = try curve.point(at: 0.25, tolerance: tolerance)
        let tangentPlane = Surface3D.analytic(.plane(
            origin: tangentPoint,
            normal: .unitX
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentPlane,
            options: CurveSurfaceIntersectionOptions(
                curveRange: try ScalarInterval(
                    lower: 0.15,
                    upper: 0.35
                )
            ),
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        let tangentIntersection = try #require(tangent.first)
        #expect(tangentIntersection.kind == .tangent)
        #expect(
            (tangentIntersection.point - tangentPoint).length
                <= tolerance.distance
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedBranchEnclosesEndpointNearAndTrimmedSpatialDifferentials() throws {
        let exact = try #require(try boundedCurves().first)
        guard case let .sphereCylinder(source) = exact.definition else {
            Issue.record("Expected a certified sphere-cylinder curve.")
            return
        }
        #expect(source.componentKind == .boundedAngularInterval)
        for fraction in [
            0.0,
            1.0e-12,
            1.0e-9,
            1.0e-6,
            0.25,
            0.5,
            1.0 - 1.0e-6,
            1.0 - 1.0e-9,
            1.0 - 1.0e-12,
            1.0,
        ] {
            let geometry = try source.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let sphereResidual = try source.sphereSurface
                .parameterProjection(
                    of: geometry.position,
                    tolerance: tolerance
                ).residual
            let cylinderResidual = try source.cylinderSurface
                .parameterProjection(
                    of: geometry.position,
                    tolerance: tolerance
                ).residual
            #expect(geometry.firstDerivative.length > tolerance.distance)
            #expect(
                max(sphereResidual, cylinderResidual)
                    <= source.maximumResidualUpperBound
            )
        }

        for trim in [
            (start: 0.0, end: 1.0),
            (start: 0.08, end: 0.72),
            (start: 0.91, end: 0.14),
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
            let lift = SurfaceLiftCurve3D(
                surface: exact.surface(for: .first),
                parameterCurve: .certifiedAnalyticPair(pcurve)
            )
            let curve = Curve3D.surfaceLift(lift)
            let interval = try ScalarInterval(lower: 0.12, upper: 0.88)
            let certifiedSecond = try #require(
                try SurfaceLiftDifferentialBounder()
                    .secondDerivativeMagnitude(
                        lift: lift,
                        interval: interval,
                        tolerance: tolerance
                    )
            )
            for index in 0...128 {
                let fraction = Double(index) / 128.0
                let geometry = try curve.differentialGeometry(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect(geometry.firstDerivative.length <= bounds.first)
                #expect(geometry.secondDerivative.length <= bounds.second)
                if interval.contains(fraction) {
                    #expect(
                        geometry.secondDerivative.length <= certifiedSecond
                    )
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedBranchIntersectsThirdPlanesTransverselyAndTangentially() throws {
        let exact = try #require(try boundedCurves().first)
        let curve = exactCurve(exact)
        let transversePlane = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitY
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: .init(),
            tolerance: tolerance
        )
        #expect(transverse.count == 2)
        #expect(transverse.allSatisfy {
            $0.kind == .transverse
                && abs($0.point.y) <= tolerance.distance
        })

        let tangentGeometry = try curve.differentialGeometry(
            at: 0.25,
            tolerance: tolerance
        )
        let tangentNormal = try tangentGeometry.secondDerivative.normalized(
            tolerance: tolerance.distance
        )
        let tangentPlane = Surface3D.analytic(.plane(
            origin: tangentGeometry.position,
            normal: tangentNormal
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentPlane,
            options: .init(),
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        let tangentIntersection = try #require(tangent.first)
        #expect(tangentIntersection.kind == .tangent)
        #expect(
            (tangentIntersection.point - tangentGeometry.position).length
                <= tolerance.distance
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func poleSplitBranchesEncloseEndpointNearAndTrimmedSpatialDifferentials() throws {
        let exactCurves = try poleSplitCurves()
            + simpleRootPoleSplitCurves()
            + rootFreePoleSplitCurves()
            + twoSimpleRootOpenCurves()
            + twoDoubleRootOpenCurves()
        #expect(exactCurves.count == 13)
        for exact in exactCurves {
            guard case let .sphereCylinder(source) = exact.definition else {
                Issue.record("Expected a certified sphere-cylinder curve.")
                continue
            }
            #expect(
                source.componentKind == .negativeOpenAngularInterval
                    || source.componentKind == .positiveOpenAngularInterval
            )
            for fraction in [
                0.0,
                1.0e-12,
                1.0e-9,
                1.0e-6,
                0.25,
                0.5,
                1.0 - 1.0e-6,
                1.0 - 1.0e-9,
                1.0 - 1.0e-12,
                1.0,
            ] {
                let geometry = try source.differential(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let residuals = try sourceResiduals(
                    point: geometry.position,
                    sphereSurface: source.sphereSurface,
                    cylinderSurface: source.cylinderSurface
                )
                #expect(geometry.firstDerivative.length > tolerance.distance)
                let residual = max(
                    residuals.sphere,
                    residuals.cylinder
                )
                #expect(
                    residual <= source.maximumResidualUpperBound,
                    "Residual \(residual) exceeded \(source.maximumResidualUpperBound) at fraction \(fraction)."
                )
            }

            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.07, end: 0.68),
                (start: 0.92, end: 0.16),
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
                    #expect(geometry.firstDerivative.length <= bounds.first)
                    #expect(geometry.secondDerivative.length <= bounds.second)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func poleSplitBranchesIntersectLocalThirdPlanesWithVerifiedKinds() throws {
        for exact in [
            try #require(try poleSplitCurves().first),
            try #require(try simpleRootPoleSplitCurves().first),
            try #require(try rootFreePoleSplitCurves().first),
        ] {
            let curve = exactCurve(exact)
            let geometry = try curve.differentialGeometry(
                at: 0.25,
                tolerance: tolerance
            )
            let tangentDirection = try geometry.firstDerivative.normalized(
                tolerance: tolerance.distance
            )
            let transversePlane = Surface3D.analytic(.plane(
                origin: geometry.position,
                normal: tangentDirection
            ))
            let localRange = try ScalarInterval(
                lower: 0.15,
                upper: 0.35
            )
            let transverse = try DefaultCurveSurfaceIntersector()
                .intersections(
                    curve: curve,
                    surface: transversePlane,
                    options: CurveSurfaceIntersectionOptions(
                        curveRange: localRange
                    ),
                    tolerance: tolerance
                )
            #expect(transverse.count == 1)
            #expect(transverse.first?.kind == .transverse)

            let normalComponent = geometry.secondDerivative
                - tangentDirection
                    * geometry.secondDerivative.dot(tangentDirection)
            let tangentNormal = try normalComponent.normalized(
                tolerance: tolerance.distance
            )
            let tangentPlane = Surface3D.analytic(.plane(
                origin: geometry.position,
                normal: tangentNormal
            ))
            let tangent = try DefaultCurveSurfaceIntersector()
                .intersections(
                    curve: curve,
                    surface: tangentPlane,
                    options: CurveSurfaceIntersectionOptions(
                        curveRange: localRange
                    ),
                    tolerance: tolerance
                )
            #expect(tangent.count == 1)
            #expect(tangent.first?.kind == .tangent)
        }
    }

    private func rootFreeCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 3.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereCylinder(curve) = exact.definition,
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
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereCylinder(curve) = exact.definition,
                  curve.componentKind == .boundedAngularInterval else {
                return nil
            }
            return exact
        }
    }

    private func poleSplitCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.0
        ))
        return try openCurves(sphere: sphere, cylinder: cylinder)
    }

    private func rootFreePoleSplitCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let axis = try Vector3D(
            x: 0.5,
            y: 0.0,
            z: sqrt(3.0) * 0.5
        ).normalized(tolerance: tolerance.distance)
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(
                x: -sqrt(3.0) * 0.25,
                y: 0.0,
                z: 0.25
            ),
            axis: axis,
            radius: 0.5
        ))
        return try openCurves(sphere: sphere, cylinder: cylinder)
    }

    private func simpleRootPoleSplitCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.5, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        return try openCurves(sphere: sphere, cylinder: cylinder)
    }

    private func twoSimpleRootOpenCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let bounded = try #require(try boundedCurves().first)
        guard case let .sphereCylinder(source) = bounded.definition else {
            return []
        }
        return try [
            CertifiedSphereCylinderIntersectionCurve.ComponentKind
                .negativeOpenAngularInterval,
            .positiveOpenAngularInterval,
        ].map { componentKind in
            let curve = try CertifiedSphereCylinderIntersectionCurve(
                sphereSurface: source.sphereSurface,
                cylinderSurface: source.cylinderSurface,
                componentKind: componentKind,
                lowerAngle: source.lowerAngle,
                upperAngle: source.upperAngle,
                tolerance: tolerance
            )
            return try CertifiedAnalyticAnalyticIntersectionCurve(
                sphereCylinderCurve: curve,
                firstSurface: source.sphereSurface,
                secondSurface: source.cylinderSurface,
                tolerance: tolerance
            )
        }
    }

    private func twoDoubleRootOpenCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.5, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        return try [
            CertifiedSphereCylinderIntersectionCurve.ComponentKind
                .negativeOpenAngularInterval,
            .positiveOpenAngularInterval,
        ].map { componentKind in
            let curve = try CertifiedSphereCylinderIntersectionCurve(
                sphereSurface: sphere,
                cylinderSurface: cylinder,
                componentKind: componentKind,
                lowerAngle: Double.pi * 1.5,
                upperAngle: Double.pi * 3.5,
                tolerance: tolerance
            )
            return try CertifiedAnalyticAnalyticIntersectionCurve(
                sphereCylinderCurve: curve,
                firstSurface: sphere,
                secondSurface: cylinder,
                tolerance: tolerance
            )
        }
    }

    private func openCurves(
        sphere: Surface3D,
        cylinder: Surface3D
    ) throws -> [CertifiedAnalyticAnalyticIntersectionCurve] {
        try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereCylinder(curve) = exact.definition,
                  curve.componentKind == .negativeOpenAngularInterval
                    || curve.componentKind
                        == .positiveOpenAngularInterval else {
                return nil
            }
            return exact
        }
    }

    private func exactCurve(
        _ exact: CertifiedAnalyticAnalyticIntersectionCurve
    ) -> Curve3D {
        .surfaceLift(SurfaceLiftCurve3D(
            surface: exact.surface(for: .first),
            parameterCurve: .certifiedAnalyticPair(
                CertifiedAnalyticPairSurfaceParameterCurve(
                    validatedIntersection: exact,
                    role: .first,
                    startFraction: 0.0,
                    endFraction: 1.0
                )
            )
        ))
    }

    private func sourceResiduals(
        point: Point3D,
        sphereSurface: Surface3D,
        cylinderSurface: Surface3D
    ) throws -> (sphere: Double, cylinder: Double) {
        guard case let .sphere(sphere) =
                CanonicalAnalyticSurface(sphereSurface),
              case let .cylinder(cylinder) =
                CanonicalAnalyticSurface(cylinderSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Sphere-cylinder residual checks require exact analytic source surfaces."
            )
        }
        let sphereResidual = abs(
            (point - sphere.center).length - sphere.radius
        )
        let axis = try cylinder.axis.normalized(
            tolerance: tolerance.distance
        )
        let offset = point - cylinder.origin
        let radial = offset - axis * offset.dot(axis)
        return (
            sphereResidual,
            abs(radial.length - cylinder.radius)
        )
    }
}
