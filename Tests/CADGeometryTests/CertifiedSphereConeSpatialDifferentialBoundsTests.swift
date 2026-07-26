import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedSphereConeSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func rootFreeBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try rootFreeCurves()
        #expect(exactCurves.count == 2)
        let componentKinds:
            Set<CertifiedSphereConeIntersectionCurve.ComponentKind> =
                Set(exactCurves.compactMap { exact in
                    guard case let .sphereCone(curve) = exact.definition else {
                        return nil
                    }
                    return curve.componentKind
                })
        let expectedKinds:
            Set<CertifiedSphereConeIntersectionCurve.ComponentKind> = [
            .negativeFullBranch,
            .positiveFullBranch,
        ]
        #expect(componentKinds == expectedKinds)

        for exact in exactCurves {
            guard case let .sphereCone(source) = exact.definition else {
                Issue.record("Expected a certified sphere-cone curve.")
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
    func rootFreeBranchIntersectsLocalTransverseAndTangentPlanes() throws {
        let exact = try #require(try rootFreeCurves().first {
            guard case let .sphereCone(curve) = $0.definition else {
                return false
            }
            return curve.componentKind == .positiveFullBranch
        })
        let curve = exactCurve(exact)
        let parameter = 0.25
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let transverseNormal = try geometry.firstDerivative.normalized(
            tolerance: tolerance.distance
        )
        let transversePlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: transverseNormal
        ))
        let localRange = try ScalarInterval(lower: 0.2, upper: 0.3)
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: CurveSurfaceIntersectionOptions(
                curveRange: localRange,
                maximumSubdivisionDepth: 24
            ),
            tolerance: tolerance
        )
        #expect(transverse.count == 1)
        let transverseIntersection = try #require(transverse.first)
        #expect(transverseIntersection.kind == .transverse)
        #expect(
            (transverseIntersection.point - geometry.position).length
                <= tolerance.distance
        )

        let tangentSquared = geometry.firstDerivative.dot(
            geometry.firstDerivative
        )
        let normalCurvature = geometry.secondDerivative
            - geometry.firstDerivative * (
                geometry.secondDerivative.dot(geometry.firstDerivative)
                    / tangentSquared
            )
        let tangentNormal = try normalCurvature.normalized(
            tolerance: tolerance.distance
        )
        let tangentPlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: tangentNormal
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentPlane,
            options: CurveSurfaceIntersectionOptions(
                curveRange: localRange,
                maximumSubdivisionDepth: 24
            ),
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        let tangentIntersection = try #require(tangent.first)
        #expect(tangentIntersection.kind == .tangent)
        #expect(
            (tangentIntersection.point - geometry.position).length
                <= tolerance.distance
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedBranchEnclosesEndpointAndTrimmedSpatialDifferentials() throws {
        let exact = try #require(try boundedCurves().first)
        guard case let .sphereCone(source) = exact.definition else {
            Issue.record("Expected a certified bounded sphere-cone curve.")
            return
        }
        #expect(source.componentKind == .boundedAngularInterval)

        for trim in [
            (start: 0.0, end: 1.0),
            (start: 0.05, end: 0.45),
            (start: 0.95, end: 0.55),
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

    @Test(.timeLimit(.minutes(1)))
    func apexReducedBranchesEncloseSpatialDifferentials() throws {
        let exactCurves = try apexReducedCurves()
        #expect(exactCurves.count == 2)
        for exact in exactCurves {
            guard case let .sphereCone(source) = exact.definition else {
                Issue.record("Expected a certified apex-reduced sphere-cone curve.")
                continue
            }
            #expect(source.componentKind == .apexReducedAngularInterval)
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: .first,
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
        try expectLocalPlaneIntersections(try #require(exactCurves.first))
    }

    @Test(.timeLimit(.minutes(1)))
    func openBranchesEnclosePoleAndSimpleRootSpatialDifferentials() throws {
        let fixtures = try poleToPoleOpenCurves()
            + simpleRootToPoleOpenCurves()
        #expect(fixtures.count == 5)
        for exact in fixtures {
            guard case let .sphereCone(source) = exact.definition else {
                Issue.record("Expected a certified open sphere-cone curve.")
                continue
            }
            let bounds = try source.openBranchSpatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: .first,
                tolerance: tolerance
            )
            #expect(pcurve.hasSpatialDifferentialMagnitudeBounds)
            let lift = SurfaceLiftCurve3D(
                surface: exact.surface(for: .first),
                parameterCurve: .certifiedAnalyticPair(pcurve)
            )
            let liftedBounds = try pcurve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            for index in 0...128 {
                let fraction = Double(index) / 128.0
                let geometry = try source.differential(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let lifted = try lift.differentialGeometry(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                #expect(geometry.firstDerivative.length <= bounds.first)
                #expect(geometry.secondDerivative.length <= bounds.second)
                #expect(lifted.firstDerivative.length <= liftedBounds.first)
                #expect(lifted.secondDerivative.length <= liftedBounds.second)
                #expect(
                    (lifted.position - geometry.position).length
                        <= tolerance.distance
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func oneSidedDoubleRootOpenBranchesEncloseSpatialDifferentials() throws {
        let exactCurves = try doubleRootToPoleOpenCurves()
        #expect(exactCurves.count == 2)

        for exact in exactCurves {
            let source = try #require(exact.sphereConeCurve)
            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.0, end: 0.7),
                (start: 0.8, end: 0.1),
            ] {
                let lower = min(trim.start, trim.end)
                let upper = max(trim.start, trim.end)
                let sourceBounds = try source
                    .openBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: lower,
                        toNormalizedFraction: upper,
                        tolerance: tolerance
                    )
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
                #expect(
                    bounds.second
                        >= sourceBounds.second * scale * scale
                )

                for index in 0...128 {
                    let fraction = Double(index) / 128.0
                    let sourceFraction = trim.start
                        + (trim.end - trim.start) * fraction
                    let geometry = try source.differential(
                        atNormalizedFraction: sourceFraction,
                        tolerance: tolerance
                    )
                    #expect(
                        geometry.firstDerivative.length
                            <= sourceBounds.first
                    )
                    #expect(
                        geometry.secondDerivative.length
                            <= sourceBounds.second
                    )
                }
            }
        }
        try expectLocalPlaneIntersections(try #require(exactCurves.first))
    }

    @Test(.timeLimit(.minutes(1)))
    func openBranchIntersectsLocalTransverseAndTangentPlanes() throws {
        let exact = try #require(try simpleRootToPoleOpenCurves().first)
        try expectLocalPlaneIntersections(exact)
    }

    private func expectLocalPlaneIntersections(
        _ exact: CertifiedAnalyticAnalyticIntersectionCurve
    ) throws {
        let curve = exactCurve(exact)
        let parameter = 0.25
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let localRange = try ScalarInterval(lower: 0.2, upper: 0.3)
        let transverseNormal = try geometry.firstDerivative.normalized(
            tolerance: tolerance.distance
        )
        let transversePlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: transverseNormal
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: CurveSurfaceIntersectionOptions(
                curveRange: localRange,
                maximumSubdivisionDepth: 24
            ),
            tolerance: tolerance
        )
        #expect(transverse.count == 1)
        #expect(try #require(transverse.first).kind == .transverse)

        let tangentSquared = geometry.firstDerivative.dot(
            geometry.firstDerivative
        )
        let normalCurvature = geometry.secondDerivative
            - geometry.firstDerivative * (
                geometry.secondDerivative.dot(geometry.firstDerivative)
                    / tangentSquared
            )
        let tangentNormal = try normalCurvature.normalized(
            tolerance: tolerance.distance
        )
        let tangentPlane = Surface3D.analytic(.plane(
            origin: geometry.position,
            normal: tangentNormal
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentPlane,
            options: CurveSurfaceIntersectionOptions(
                curveRange: localRange,
                maximumSubdivisionDepth: 24
            ),
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        let tangentIntersection = try #require(tangent.first)
        #expect(tangentIntersection.kind == .tangent)
        #expect(
            (tangentIntersection.point - geometry.position).length
                <= tolerance.distance
        )
    }

    private func rootFreeCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 3.0
        ))
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 1.0, y: 0.0, z: -4.0),
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereCone(curve) = exact.definition,
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
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 2.0, y: 0.0, z: -4.0),
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereCone(curve) = exact.definition,
                  curve.componentKind == .boundedAngularInterval else {
                return nil
            }
            return exact
        }
    }

    private func apexReducedCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 1.0
        ))
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereCone(curve) = exact.definition,
                  curve.componentKind == .apexReducedAngularInterval else {
                return nil
            }
            return exact
        }
    }

    private func poleToPoleOpenCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        try openCurves(
            sphereRadius: 2.0,
            coneApex: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )
    }

    private func simpleRootToPoleOpenCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        try openCurves(
            sphereRadius: 2.0,
            coneApex: Point3D(x: 3.0, y: 0.0, z: -4.0)
        )
    }

    private func doubleRootToPoleOpenCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let radius = 2.0
        let slope = 0.5
        let scale = sqrt(1.0 + slope * slope)
        let axialOffset = radius * (scale - slope) / (2.0 * slope)
        let radialOffset = slope * (radius + axialOffset)
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: radius
        ))
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(
                x: radialOffset,
                y: 0.0,
                z: -axialOffset
            ),
            axis: .unitZ,
            halfAngle: atan(slope)
        ))
        let poleAngle = Double.pi * 0.5
        let doubleRootAngle = Double.pi * 1.5
        return try [
            (poleAngle, doubleRootAngle),
            (doubleRootAngle, poleAngle + 2.0 * Double.pi),
        ].map { lower, upper in
            let curve = try CertifiedSphereConeIntersectionCurve(
                sphereSurface: sphere,
                coneSurface: cone,
                componentKind: .positiveOpenAngularInterval,
                lowerAngle: lower,
                upperAngle: upper,
                tolerance: tolerance
            )
            return try CertifiedAnalyticAnalyticIntersectionCurve(
                sphereConeCurve: curve,
                firstSurface: sphere,
                secondSurface: cone,
                tolerance: tolerance
            )
        }
    }

    private func openCurves(
        sphereRadius: Double,
        coneApex: Point3D
    ) throws -> [CertifiedAnalyticAnalyticIntersectionCurve] {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: sphereRadius
        ))
        let cone = Surface3D.analytic(.cone(
            apex: coneApex,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereCone(curve) = exact.definition,
                  curve.componentKind == .negativeOpenAngularInterval
                    || curve.componentKind == .positiveOpenAngularInterval else {
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
}
