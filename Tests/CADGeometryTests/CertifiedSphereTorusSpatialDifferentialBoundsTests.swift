import CADCore
@testable import CADGeometry
import Testing

struct CertifiedSphereTorusSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

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
    func endpointRegularizedComponentRemainsExplicitlyUnsupported() throws {
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
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            tolerance: tolerance
        )
        #expect(pcurve.hasSpatialDifferentialMagnitudeBounds == false)
        do {
            _ = try pcurve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            Issue.record(
                "Endpoint-regularized sphere-torus bounds must not report success before their separate certificate is implemented."
            )
        } catch let error as KernelError {
            #expect(error.code == .unsupportedCapability)
        }
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
}
