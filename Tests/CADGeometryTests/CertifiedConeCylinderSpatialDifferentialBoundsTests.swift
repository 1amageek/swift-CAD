import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedConeCylinderSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func rootFreeBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try rootFreeCurves()
        #expect(exactCurves.count == 2)
        let componentKinds:
            Set<CertifiedConeCylinderIntersectionCurve.ComponentKind> =
                Set(exactCurves.compactMap { exact in
                    guard case let .coneCylinder(curve) = exact.definition
                    else {
                        return nil
                    }
                    return curve.componentKind
                })
        let expectedKinds:
            Set<CertifiedConeCylinderIntersectionCurve.ComponentKind> = [
            .negativeFullBranch,
            .positiveFullBranch,
        ]
        #expect(componentKinds == expectedKinds)

        for exact in exactCurves {
            guard case let .coneCylinder(source) = exact.definition else {
                Issue.record("Expected a certified cone-cylinder curve.")
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
            guard case let .coneCylinder(curve) = $0.definition else {
                return false
            }
            return curve.componentKind == .positiveFullBranch
        })
        let curve = exact.curve
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
            options: CurveSurfaceIntersectionOptions(curveRange: localRange),
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
            options: CurveSurfaceIntersectionOptions(curveRange: localRange),
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        #expect(tangent.first?.kind == .tangent)
    }

    @Test(.timeLimit(.minutes(1)))
    func rulingParallelBranchEnclosesDifferentialsAndIntersectsPlanes()
        throws
    {
        let exact = try rulingParallelCurve()
        let source = try #require(exact.coneCylinderCurve)
        #expect(source.componentKind == .rulingParallelLinear)
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
                let fraction = Double(index) / 128.0
                let geometry = try curve.differentialGeometry(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect(geometry.firstDerivative.length <= bounds.first)
                #expect(geometry.secondDerivative.length <= bounds.second)
            }
        }

        let curve = exact.curve
        let parameter = 0.25
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let localRange = try ScalarInterval(lower: 0.2, upper: 0.3)
        let options = CurveSurfaceIntersectionOptions(
            curveRange: localRange,
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
    func boundedBranchesEncloseEndpointDifferentialsAndIntersectPlanes()
        throws
    {
        let exactCurves = try boundedCurves()
        #expect(exactCurves.count == 2)
        for exact in exactCurves {
            let source = try #require(exact.coneCylinderCurve)
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

        let exact = try #require(exactCurves.first)
        let curve = exact.curve
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
    func apexNodeBranchesEncloseEndpointDifferentials() throws {
        let exactCurves = try apexNodeCurves()
        #expect(exactCurves.count == 2)
        let componentKinds = Set(exactCurves.compactMap {
            $0.coneCylinderCurve?.componentKind
        })
        #expect(componentKinds == [
            .apexLowerNodeInterval,
            .apexUpperNodeInterval,
        ])
        for exact in exactCurves {
            let source = try #require(exact.coneCylinderCurve)
            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.05, end: 0.65),
                (start: 0.9, end: 0.1),
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
                let sourceBounds = try source
                    .apexNodeSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(trim.start, trim.end),
                        toNormalizedFraction: max(trim.start, trim.end),
                        tolerance: tolerance
                    )
                let scale = abs(trim.end - trim.start)
                #expect(bounds.first >= sourceBounds.first * scale)
                #expect(bounds.second
                    >= sourceBounds.second * scale * scale)

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
    }

    // Certified apex-branch bounds run close to a minute in unoptimized
    // builds under suite load.
    @Test(.timeLimit(.minutes(3)))
    func apexNodeBranchIntersectsLocalTransverseAndTangentPlanes() throws {
        let exact = try #require(try apexNodeCurves().first)
        let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .second,
            tolerance: tolerance
        )
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: exact.surface(for: .second),
            parameterCurve: .certifiedAnalyticPair(pcurve)
        ))
        let parameter = 0.25
        let geometry = try curve.differentialGeometry(
            at: parameter,
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

    private func rootFreeCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let componentKinds:
            [CertifiedConeCylinderIntersectionCurve.ComponentKind] = [
            .negativeFullBranch,
            .positiveFullBranch,
        ]
        return try componentKinds.map { componentKind in
            let curve = try CertifiedConeCylinderIntersectionCurve(
                coneSurface: cone,
                cylinderSurface: cylinder,
                componentKind: componentKind,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                tolerance: tolerance
            )
            return try CertifiedAnalyticAnalyticIntersectionCurve(
                coneCylinderCurve: curve,
                firstSurface: cone,
                secondSurface: cylinder,
                tolerance: tolerance
            )
        }
    }

    private func rulingParallelCurve()
        throws -> CertifiedAnalyticAnalyticIntersectionCurve
    {
        let halfAngle = atan(0.5)
        let rulingDirection = Vector3D(
            x: sin(halfAngle),
            y: 0.0,
            z: cos(halfAngle)
        )
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 4.0),
            axis: rulingDirection,
            radius: 1.0
        ))
        let result = try DefaultSurfaceSurfaceIntersector().intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        )
        guard result.count == 1,
              case let .curve(intersection) = result[0],
              case let .analyticAnalytic(exact) = intersection.truth,
              let source = exact.coneCylinderCurve,
              source.componentKind == .rulingParallelLinear else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Expected a ruling-parallel cone-cylinder analytic truth curve."
            )
        }
        return exact
    }

    private func boundedCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 1.5),
            axis: .unitY,
            radius: 1.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  let curve = exact.coneCylinderCurve,
                  curve.componentKind == .boundedAngularInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a bounded cone-cylinder analytic truth curve."
                )
            }
            return exact
        }
    }

    private func apexNodeCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  let curve = exact.coneCylinderCurve,
                  curve.componentKind == .apexLowerNodeInterval
                    || curve.componentKind == .apexUpperNodeInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a cone-cylinder apex-node analytic truth curve."
                )
            }
            return exact
        }
    }
}
