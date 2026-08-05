import CADCore
@testable import CADGeometry
import Testing

struct CertifiedGeneralTorusCylinderSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    // Certified trimmed-branch enclosure runs half a minute alone and past
    // two minutes under full-suite load in unoptimized builds.
    @Test(.timeLimit(.minutes(4)))
    func certifiedBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try curves()
        #expect(exactCurves.count == 2)

        for exact in exactCurves {
            guard case let .generalTorusCylinder(source) = exact.definition else {
                Issue.record("Expected a certified general torus-cylinder curve.")
                continue
            }
            let sourceBounds = try source.spatialDifferentialMagnitudeBounds(
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
    func certifiedBranchIntersectsLocalTransverseAndTangentPlanes() throws {
        let exact = try #require(try curves().first)
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
    func insufficientCertificateCellBudgetFailsExplicitly() throws {
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let cylinderAxis = try Vector3D(
            x: 0.08,
            y: 0.0,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: cylinderAxis,
            radius: 3.0
        ))

        do {
            _ = try CertifiedGeneralTorusCylinderIntersectionCurve(
                torusSurface: torus,
                cylinderSurface: cylinder,
                branchIndex: 0,
                maximumSubdivisionDepth: 24,
                maximumCellCount: 1,
                tolerance: tolerance
            )
            Issue.record("Expected the general torus-cylinder certificate cell budget to fail.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
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
        let cylinderAxis = try Vector3D(
            x: 0.08,
            y: 0.0,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: cylinderAxis,
            radius: 3.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .generalTorusCylinder = exact.definition else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a regular general torus-cylinder truth curve."
                )
            }
            return exact
        }
    }
}
