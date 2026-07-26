import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedGeneralConeTorusSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(4)))
    func certifiedRegularBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try curves()
        #expect(exactCurves.count == 4)

        for exact in exactCurves {
            guard case let .generalConeTorus(source) = exact.definition else {
                Issue.record("Expected a certified general cone-torus curve.")
                continue
            }
            #expect(source.apexReduction == nil)
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

    @Test(.timeLimit(.minutes(3)))
    func certifiedRegularBranchIntersectsLocalTransverseAndTangentPlanes() throws {
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
        do {
            _ = try CertifiedGeneralConeTorusIntersectionCurve(
                coneSurface: coneSurface(),
                torusSurface: torusSurface(),
                branchIndex: 0,
                maximumSubdivisionDepth: 24,
                maximumCellCount: 1,
                tolerance: tolerance
            )
            Issue.record("Expected the general cone-torus certificate cell budget to fail.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rotatedAxesRemainInsideTheCertificateResourceEnvelope() throws {
        let torusAxis = try Vector3D(
            x: 0.2,
            y: 0.3,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let radial = try torusAxis.cross(.unitX).normalized(
            tolerance: tolerance.distance
        )
        let coneAxis = try (torusAxis + radial * 0.05).normalized(
            tolerance: tolerance.distance
        )
        let center = Point3D(x: 0.5, y: -0.25, z: 0.75)
        let curve = try CertifiedGeneralConeTorusIntersectionCurve(
            coneSurface: .analytic(.cone(
                apex: center,
                axis: coneAxis,
                halfAngle: atan(6.0)
            )),
            torusSurface: .analytic(.torus(
                center: center,
                axis: torusAxis,
                majorRadius: 3.0,
                minorRadius: 1.0
            )),
            branchIndex: 0,
            tolerance: tolerance
        )

        #expect(curve.branchCount == 4)
        let bounds = try curve.spatialDifferentialMagnitudeBounds(
            tolerance: tolerance
        )
        #expect(bounds.first.isFinite)
        #expect(bounds.second.isFinite)
    }

    @Test(.timeLimit(.minutes(4)))
    func apexReducedBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try apexCurves()
        #expect(exactCurves.count == 3)
        for exact in exactCurves {
            guard case let .generalConeTorus(source) = exact.definition,
                  let reduction = source.apexReduction else {
                Issue.record("Expected a certified cone-torus apex reduction.")
                continue
            }
            let sourceBounds = try reduction
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
                #expect(pcurve.hasSpatialDifferentialMagnitudeBounds)
                let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
                let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                    surface: exact.surface(for: .first),
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                ))
                for index in 0...128 {
                    let geometry: Curve3D.DifferentialGeometry
                    do {
                        geometry = try curve.differentialGeometry(
                            at: Double(index) / 128.0,
                            tolerance: tolerance
                        )
                    } catch {
                        Issue.record(
                            "Failed \(reduction.componentKind.rawValue) trim \(trim.start)...\(trim.end) at sample \(index): \(error)"
                        )
                        throw error
                    }
                    #expect(geometry.firstDerivative.length <= bounds.first)
                    #expect(geometry.secondDerivative.length <= bounds.second)
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(2)))
    func generatorFoldRemainsContinuousAcrossRegularizedJoins() throws {
        let exact = try #require(try apexCurves().first { exact in
            exact.generalConeTorusCurve?.apexReduction?.componentKind
                == .generatorTangencyInterval
        })
        let reduction = try #require(
            exact.generalConeTorusCurve?.apexReduction
        )
        let bounds = try reduction.spatialDifferentialMagnitudeBounds(
            tolerance: tolerance
        )
        for pair in [
            (join: 0.0, nearby: 1.0e-8),
            (join: 0.5, nearby: 0.5 - 1.0e-8),
            (join: 0.5, nearby: 0.5 + 1.0e-8),
            (join: 1.0, nearby: 1.0 - 1.0e-8),
        ] {
            let join = try reduction.differential(
                atNormalizedFraction: pair.join,
                tolerance: tolerance
            )
            let nearby = try reduction.differential(
                atNormalizedFraction: pair.nearby,
                tolerance: tolerance
            )
            let distance = abs(pair.nearby - pair.join)
            #expect(
                (nearby.position - join.position).length
                    <= bounds.first * distance
            )
            #expect(
                (nearby.firstDerivative - join.firstDerivative).length
                    <= bounds.second * distance,
                "Derivative delta \((nearby.firstDerivative - join.firstDerivative).length) exceeded \(bounds.second * distance) near join \(pair.join)."
            )
            for surface in [reduction.coneSurface, reduction.torusSurface] {
                let projection = try surface.parameterProjection(
                    of: nearby.position,
                    tolerance: tolerance
                )
                #expect(projection.residual <= tolerance.distance)
            }
        }
    }

    @Test(.timeLimit(.minutes(4)))
    func apexReducedBranchesIntersectLocalTransverseAndTangentPlanes() throws {
        for exact in try apexCurves() {
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
                curveRange: try ScalarInterval(
                    lower: 0.249,
                    upper: 0.251
                ),
                maximumSubdivisionDepth: 24
            )
            let transversePlane = Surface3D.analytic(.plane(
                origin: geometry.position,
                normal: try geometry.firstDerivative.normalized(
                    tolerance: tolerance.distance
                )
            ))
            let transverse = try DefaultCurveSurfaceIntersector()
                .intersections(
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
                    geometry.secondDerivative.dot(
                        geometry.firstDerivative
                    ) / tangentSquared
                )
            let tangentPlane = Surface3D.analytic(.plane(
                origin: geometry.position,
                normal: try normalCurvature.normalized(
                    tolerance: tolerance.distance
                )
            ))
            let tangent = try DefaultCurveSurfaceIntersector()
                .intersections(
                    curve: curve,
                    surface: tangentPlane,
                    options: options,
                    tolerance: tolerance
                )
            #expect(tangent.count == 1)
            #expect(tangent.first?.kind == .tangent)
        }
    }

    private func curves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        try DefaultSurfaceSurfaceIntersector().intersections(
            first: coneSurface(),
            second: torusSurface(),
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .generalConeTorus(source) = exact.definition,
                  source.apexReduction == nil else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a regular general cone-torus truth curve."
                )
            }
            return exact
        }
    }

    private func apexCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let axis = try Vector3D(
            x: 0.05,
            y: 0.0,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 4.0, y: 0.0, z: 0.0),
            axis: axis,
            halfAngle: atan(6.0)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: cone,
            second: torusSurface(),
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .generalConeTorus(source) = exact.definition,
                  source.apexReduction != nil else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a cone-torus apex-reduction truth curve."
                )
            }
            return exact
        }
    }

    private func coneSurface() throws -> Surface3D {
        .analytic(.cone(
            apex: .origin,
            axis: try Vector3D(
                x: 0.05,
                y: 0.0,
                z: 1.0
            ).normalized(tolerance: tolerance.distance),
            halfAngle: atan(6.0)
        ))
    }

    private func torusSurface() -> Surface3D {
        .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
    }
}
