import CADCore
@testable import CADGeometry
import Testing

struct CertifiedParallelTorusTorusSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(2)))
    func regularBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try regularCurves()
        #expect(exactCurves.count == 4)

        for exact in exactCurves {
            guard case let .parallelTorusTorus(source) = exact.definition else {
                Issue.record(
                    "Expected a certified parallel torus-torus curve."
                )
                continue
            }
            #expect(source.componentKind == .regularClosed)
            let sourceBounds = try source
                .spatialDifferentialMagnitudeBounds(
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
    func regularBranchIntersectsLocalTransverseAndTangentPlanes() throws {
        let exact = try #require(try regularCurves().first)
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
            curveRange: try ScalarInterval(lower: 0.249, upper: 0.251),
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
    func nodalBranchesRemainExplicitlyUnsupported() throws {
        let exactCurves = try exactCurves(offset: 2.0)
        #expect(exactCurves.count == 4)
        for exact in exactCurves {
            guard case let .parallelTorusTorus(source) = exact.definition else {
                Issue.record("Expected a nodal parallel torus-torus curve.")
                continue
            }
            #expect(source.componentKind == .nodalSelfLoop)
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
                    "Nodal torus-torus bounds must not report success before their endpoint-aware certificate is implemented."
                )
            } catch let error as KernelError {
                #expect(error.code == .unsupportedCapability)
            }
        }
    }

    private func regularCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        try exactCurves(offset: 2.2)
    }

    private func exactCurves(
        offset: Double
    ) throws -> [CertifiedAnalyticAnalyticIntersectionCurve] {
        let first = torus(
            center: .origin,
            minorRadius: 0.5
        )
        let second = torus(
            center: Point3D(x: offset, y: 0.0, z: 0.0),
            minorRadius: 1.5
        )
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .parallelTorusTorus = exact.definition else {
                return nil
            }
            return exact
        }
    }

    private func torus(
        center: Point3D,
        minorRadius: Double
    ) -> Surface3D {
        .analytic(.torus(
            center: center,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: minorRadius
        ))
    }
}
