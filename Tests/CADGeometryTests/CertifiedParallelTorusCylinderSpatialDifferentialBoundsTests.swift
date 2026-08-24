import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedParallelTorusCylinderSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(3)))
    func thirdDerivativesCoverRootFreeAndSingularEndpointStructures() throws {
        let exactCurves = try curves()
            + [boundedCurve()]
            + internalTangencyCurves(offset: 3.0, radius: 1.0)
            + internalTangencyCurves(offset: 3.5, radius: 1.5)
        #expect(exactCurves.count >= 5)
        for exact in exactCurves {
            guard case let .parallelTorusCylinder(curve) = exact.definition else {
                Issue.record(
                    "Expected a certified parallel torus-cylinder curve."
                )
                continue
            }
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: .first,
                tolerance: tolerance
            )
            let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let third = try #require(bounds.third)
            for fraction in [0.0, 0.23, 0.5, 0.57, 1.0] {
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
                        <= max(8.0e-4, scale * 4.0e-6),
                    "component: \(curve.componentKind), fraction: \(fraction), magnitude: \(scale)"
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rootFreeBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try curves()
        #expect(exactCurves.count == 2)
        let componentKinds:
            Set<CertifiedParallelTorusCylinderIntersectionCurve.ComponentKind> =
                Set(exactCurves.compactMap { exact in
                    guard case let .parallelTorusCylinder(curve)
                            = exact.definition else {
                        return nil
                    }
                    return curve.componentKind
                })
        let expectedKinds:
            Set<CertifiedParallelTorusCylinderIntersectionCurve.ComponentKind> = [
            .negativeFullBranch,
            .positiveFullBranch,
        ]
        #expect(componentKinds == expectedKinds)

        for exact in exactCurves {
            guard case let .parallelTorusCylinder(source) = exact.definition else {
                Issue.record("Expected a certified parallel torus-cylinder curve.")
                continue
            }
            let sourceBounds = try source
                .fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            let sourceThird = try #require(sourceBounds.third)
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
                let third = try #require(bounds.third)
                #expect(third >= sourceThird * scale * scale * scale)

                let lift = SurfaceLiftCurve3D(
                    surface: exact.surface(for: .first),
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                )
                let curve = Curve3D.surfaceLift(lift)
                let interval = try ScalarInterval(lower: 0.15, upper: 0.85)
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
                    let thirdDerivative = try curve
                        .parameterDerivativesThroughThirdOrder(
                            at: fraction,
                            tolerance: tolerance
                        ).thirdDerivative
                    #expect(thirdDerivative.length <= third)
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
        let exact = try #require(try curves().first {
            guard case let .parallelTorusCylinder(curve) = $0.definition else {
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
            at: 0.25,
            tolerance: tolerance
        )
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(lower: 0.2, upper: 0.3),
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
    func boundedBranchEnclosesEndpointDifferentials() throws {
        let exact = try boundedCurve()
        guard case let .parallelTorusCylinder(source) = exact.definition else {
            Issue.record("Expected a bounded parallel torus-cylinder curve.")
            return
        }
        #expect(source.componentKind == .boundedAngularInterval)
        for trim in [
            (start: 0.0, end: 1.0),
            (start: 0.1, end: 0.7),
            (start: 0.85, end: 0.15),
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

    @Test(.timeLimit(.minutes(1)))
    func boundedBranchIntersectsLocalTransverseAndTangentPlanes() throws {
        let exact = try boundedCurve()
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            tolerance: tolerance
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: exact.surface(for: .first),
            parameterCurve: .certifiedAnalyticPair(pcurve)
        ))
        let parameter = 0.253
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(lower: 0.25, upper: 0.257),
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
    func internalTangencyBranchesEncloseEndpointDifferentials() throws {
        for fixture in [
            (offset: 3.0, radius: 1.0),
            (offset: 3.5, radius: 1.5),
        ] {
            let exactCurves = try internalTangencyCurves(
                offset: fixture.offset,
                radius: fixture.radius
            )
            #expect(exactCurves.isEmpty == false)
            for exact in exactCurves {
                guard case let .parallelTorusCylinder(source)
                        = exact.definition else {
                    Issue.record(
                        "Expected an internal-tangency torus-cylinder curve."
                    )
                    continue
                }
                #expect(
                    source.componentKind
                        == .negativeInternalTangencyInterval
                    || source.componentKind
                        == .positiveInternalTangencyInterval
                )
                for trim in [
                    (start: 0.0, end: 1.0),
                    (start: 0.1, end: 0.7),
                    (start: 0.85, end: 0.15),
                ] {
                    let pcurve =
                        try CertifiedAnalyticPairSurfaceParameterCurve(
                            intersection: exact,
                            role: .first,
                            startFraction: trim.start,
                            endFraction: trim.end,
                            tolerance: tolerance
                        )
                    #expect(pcurve.hasSpatialDifferentialMagnitudeBounds)
                    let bounds = try pcurve
                        .spatialDifferentialMagnitudeBounds(
                            tolerance: tolerance
                        )
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
    }

    @Test(.timeLimit(.minutes(1)))
    func internalTangencyBranchIntersectsLocalTransverseAndTangentPlanes()
        throws
    {
        let exact = try #require(
            try internalTangencyCurves(offset: 3.0, radius: 1.0).first
        )
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            tolerance: tolerance
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: exact.surface(for: .first),
            parameterCurve: .certifiedAnalyticPair(pcurve)
        ))
        let parameter = 0.25
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(lower: 0.2495, upper: 0.2505),
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

    private func curves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.2, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 3.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .parallelTorusCylinder = exact.definition else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a root-free parallel torus-cylinder truth curve."
                )
            }
            return exact
        }
    }

    private func boundedCurve()
        throws -> CertifiedAnalyticAnalyticIntersectionCurve
    {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 4.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.0
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector()
            .intersections(
                first: torus,
                second: cylinder,
                tolerance: tolerance
            )
        guard intersections.count == 1,
              case let .curve(result) = intersections[0],
              case let .analyticAnalytic(exact) = result.truth,
              case let .parallelTorusCylinder(source) = exact.definition,
              source.componentKind == .boundedAngularInterval else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Expected a bounded parallel torus-cylinder truth curve."
            )
        }
        return exact
    }

    private func internalTangencyCurves(
        offset: Double,
        radius: Double
    ) throws -> [CertifiedAnalyticAnalyticIntersectionCurve] {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: offset, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: radius
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .parallelTorusCylinder(source) = exact.definition,
                  source.componentKind == .negativeInternalTangencyInterval
                    || source.componentKind
                        == .positiveInternalTangencyInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected an internal-tangency parallel torus-cylinder truth curve."
                )
            }
            return exact
        }
    }

    private func secondDerivativeDifference(
        curve: CertifiedParallelTorusCylinderIntersectionCurve,
        at fraction: Double
    ) throws -> Vector3D {
        let endpointStep = 2.0e-3
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
        if abs(fraction - 0.5) <= tolerance.relative {
            let step = 1.0e-3
            return (
                try second(fraction - 2.0 * step)
                    - second(fraction - step) * 8.0
                    + second(fraction + step) * 8.0
                    - second(fraction + 2.0 * step)
            ) / (12.0 * step)
        }
        let interiorStep = 1.0e-5
        return (
            try second(fraction + interiorStep)
                - second(fraction - interiorStep)
        ) / (2.0 * interiorStep)
    }
}
