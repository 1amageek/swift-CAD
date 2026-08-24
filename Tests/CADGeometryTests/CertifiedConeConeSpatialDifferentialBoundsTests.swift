import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedConeConeSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func rootFreeReferenceChartPreparationMatchesProjectedPcurve() throws {
        for exact in try rootFreeCurves() {
            let source = try #require(exact.coneConeCurve)
            let preparation = try source.prepareFullBranchDifferentialBounds(
                tolerance: tolerance
            )
            let referenceRole: SurfaceIntersectionSurfaceRole =
                exact.surface(for: .first) == source.referenceSurface
                    ? .first
                    : .second
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: referenceRole,
                startFraction: 0.0,
                endFraction: 1.0,
                tolerance: tolerance
            )
            for fraction in [0.0, 0.1, 0.37, 0.73, 1.0] {
                let direct = try preparation
                    .referenceParameterAndFirstDerivative(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                let projected = try source.parameter(
                    on: source.referenceSurface,
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let differential = try pcurve.differential(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let period = 2.0 * Double.pi
                let rawAngleDelta = abs(direct.parameter.u - projected.u)
                let angleDelta = min(rawAngleDelta, period - rawAngleDelta)
                #expect(angleDelta <= tolerance.angle * 8.0)
                #expect(
                    abs(direct.parameter.v - projected.v)
                        <= tolerance.distance * 8.0
                )
                #expect(
                    abs(
                        direct.firstDerivative.y
                            - differential.firstDerivative.y
                    ) <= tolerance.relative * max(
                        abs(direct.firstDerivative.y),
                        abs(differential.firstDerivative.y),
                        1.0
                    ) * 32.0
                )
                #expect(
                    abs(
                        direct.firstDerivative.x
                            - differential.firstDerivative.x
                    ) <= tolerance.relative * max(
                        abs(direct.firstDerivative.x),
                        abs(differential.firstDerivative.x),
                        1.0
                    ) * 32.0
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rootFreeBranchesEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try rootFreeCurves()
        #expect(exactCurves.count == 2)
        let componentKinds:
            Set<CertifiedConeConeIntersectionCurve.ComponentKind> =
                Set(exactCurves.compactMap { exact in
                    guard case let .coneCone(curve) = exact.definition else {
                        return nil
                    }
                    return curve.componentKind
                })
        let expectedKinds:
            Set<CertifiedConeConeIntersectionCurve.ComponentKind> = [
            .negativeFullBranch,
            .positiveFullBranch,
        ]
        #expect(componentKinds == expectedKinds)

        for exact in exactCurves {
            guard case let .coneCone(source) = exact.definition else {
                Issue.record("Expected a certified cone-cone curve.")
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
                #expect(pcurve.hasIntervalInvariantSpatialDifferentialMagnitudeBounds)
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
                #expect(
                    SurfaceLiftDifferentialBounder()
                        .derivativeMagnitudeBoundsAreIntervalInvariant(lift: lift)
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
        let exact = try #require(try rootFreeCurves().first {
            guard case let .coneCone(curve) = $0.definition else {
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
        let localOptions = CurveSurfaceIntersectionOptions(
            curveRange: localRange,
            maximumSubdivisionDepth: 22
        )
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: localOptions,
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
            options: localOptions,
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        #expect(tangent.first?.kind == .tangent)
    }

    @Test(.timeLimit(.minutes(1)))
    func shallowTangentIsolationDepthResolvesTangentContact() throws {
        let exact = try #require(try rootFreeCurves().first {
            guard case let .coneCone(curve) = $0.definition else {
                return false
            }
            return curve.componentKind == .positiveFullBranch
        })
        let parameter = 0.25
        let geometry = try exact.curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
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

        // The stationary-point refinement escapes its leaf cell, so a
        // shallow subdivision depth still certifies the tangential contact
        // instead of exhausting its resource budget.
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: exact.curve,
            surface: tangentPlane,
            options: CurveSurfaceIntersectionOptions(
                curveRange: try ScalarInterval(lower: 0.2, upper: 0.3),
                maximumSubdivisionDepth: 8
            ),
            tolerance: tolerance
        )
        #expect(intersections.count == 1)
        #expect(intersections.first?.kind == .tangent)
        if let contact = intersections.first {
            #expect(abs(contact.curveParameter - parameter) <= 1.0e-6)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func apexReducedBranchesEncloseSpatialDifferentialsAndIntersectPlanes()
        throws
    {
        let exactCurves = try apexReducedCurves()
        #expect(exactCurves.count == 2)
        for exact in exactCurves {
            let source = try #require(exact.coneConeCurve)
            #expect(source.componentKind == .apexReducedAngularInterval)
            let sourceBounds = try source
                .apexReducedBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            let sourceThird = try #require(sourceBounds.third)
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
                #expect(pcurve.hasIntervalInvariantSpatialDifferentialMagnitudeBounds)
                let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
                let scale = abs(trim.end - trim.start)
                let third = try #require(bounds.third)
                #expect(third >= sourceThird * scale * scale * scale)
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
                    let thirdDerivative = try curve
                        .parameterDerivativesThroughThirdOrder(
                            at: fraction,
                            tolerance: tolerance
                        ).thirdDerivative
                    #expect(thirdDerivative.length <= third)
                }
            }
        }

        let exact = try #require(exactCurves.first)
        let curve = exact.curve
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

    @Test(.timeLimit(.minutes(1)))
    func boundedBranchesEncloseEndpointDifferentialsAndIntersectPlanes()
        throws
    {
        let exactCurves = try boundedCurves()
        #expect(exactCurves.count == 2)
        for exact in exactCurves {
            let source = try #require(exact.coneConeCurve)
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
                #expect(pcurve.hasIntervalInvariantSpatialDifferentialMagnitudeBounds == false)
                let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
                let sourceBounds = try source
                    .boundedBranchSpatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(trim.start, trim.end),
                        toNormalizedFraction: max(trim.start, trim.end),
                        tolerance: tolerance
                    )
                let sourceThird = try #require(sourceBounds.third)
                let scale = abs(trim.end - trim.start)
                let third = try #require(bounds.third)
                #expect(third >= sourceThird * scale * scale * scale)
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
                    let thirdDerivative = try curve
                        .parameterDerivativesThroughThirdOrder(
                            at: fraction,
                            tolerance: tolerance
                        ).thirdDerivative
                    #expect(thirdDerivative.length <= third)
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
    func analyticThirdDerivativeMatchesSecondDerivativeVariation() throws {
        let sources = try (
            rootFreeCurves() + boundedCurves() + apexReducedCurves()
        ).map { try #require($0.coneConeCurve) }
        let step = 1.0e-5
        for source in sources {
            let curve = Curve3D.certifiedIntersection(.coneCone(source))
            for fraction in [0.17, 0.37, 0.73] {
                let analytic = try curve.parameterDerivativesThroughThirdOrder(
                    at: fraction,
                    tolerance: tolerance
                ).thirdDerivative
                let lower = try curve.differentialGeometry(
                    at: fraction - step,
                    tolerance: tolerance
                ).secondDerivative
                let upper = try curve.differentialGeometry(
                    at: fraction + step,
                    tolerance: tolerance
                ).secondDerivative
                let reference = (upper - lower) / (2.0 * step)
                let scale = max(analytic.length, reference.length, 1.0)
                #expect((analytic - reference).length / scale < 2.0e-5)
            }
        }
    }

    private func rootFreeCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let first = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 0.0, y: 0.0, z: 4.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .coneCone = exact.definition else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a root-free cone-cone analytic truth curve."
                )
            }
            return exact
        }
    }

    private func apexReducedCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let first = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 2.0, y: 0.0, z: 4.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  let curve = exact.coneConeCurve,
                  curve.componentKind == .apexReducedAngularInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected an apex-reduced cone-cone analytic truth curve."
                )
            }
            return exact
        }
    }

    private func boundedCurves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let first = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 0.51, y: 0.0, z: 1.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        ).map { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  let curve = exact.coneConeCurve,
                  curve.componentKind == .boundedAngularInterval else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a bounded cone-cone analytic truth curve."
                )
            }
            return exact
        }
    }
}
