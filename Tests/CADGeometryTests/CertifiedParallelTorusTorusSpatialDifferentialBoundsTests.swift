import CADCore
@testable import CADGeometry
import Testing

struct CertifiedParallelTorusTorusSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(2)))
    func analyticThirdDerivativeMatchesSecondDerivativeVariationAwayFromJoins() throws {
        let exactCurves = try regularCurves()
            + exactCurves(offset: 2.0)
            + exactCurves(offset: 1.9999)
        for exact in exactCurves {
            guard case let .parallelTorusTorus(source) = exact.definition else {
                Issue.record("Expected a parallel torus-torus curve.")
                continue
            }
            let curve = Curve3D.certifiedIntersection(
                .parallelTorusTorus(source)
            )
            let bounds = try source.spatialDifferentialMagnitudeBounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            let third = try #require(bounds.third)
            for fraction in [0.17, 0.31, 0.73] {
                let step = 1.0e-5
                let actual = try curve.parameterDerivativesThroughThirdOrder(
                    at: fraction,
                    tolerance: tolerance
                ).thirdDerivative
                #expect(actual.length <= third)
                let lower = try curve.differentialGeometry(
                    at: fraction - step,
                    tolerance: tolerance
                ).secondDerivative
                let upper = try curve.differentialGeometry(
                    at: fraction + step,
                    tolerance: tolerance
                ).secondDerivative
                let reference = (upper - lower) / (2.0 * step)
                let scale = max(reference.length, actual.length, 1.0)
                #expect((actual - reference).length <= scale * 2.0e-5)
            }
        }
    }

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
    func nodalBranchesEncloseSpatialDifferentials() throws {
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
            #expect(pcurve.hasSpatialDifferentialMagnitudeBounds)
            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.1, end: 0.7),
                (start: 0.8, end: 0.2),
            ] {
                let trimmed = try CertifiedAnalyticPairSurfaceParameterCurve(
                    intersection: exact,
                    role: .first,
                    startFraction: trim.start,
                    endFraction: trim.end,
                    tolerance: tolerance
                )
                let bounds = try trimmed.spatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
                #expect(bounds.first.isFinite)
                #expect(bounds.second.isFinite)
                let third = try #require(bounds.third)
                let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
                    surface: exact.surface(for: .first),
                    parameterCurve: .certifiedAnalyticPair(trimmed)
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
                    let sourceFraction = trim.start
                        + (trim.end - trim.start) * fraction
                    if isNonC3Join(
                        sourceFraction,
                        componentKind: source.componentKind
                    ) {
                        #expect(throws: KernelError.self) {
                            try curve.parameterDerivativesThroughThirdOrder(
                                at: fraction,
                                tolerance: tolerance
                            )
                        }
                    } else {
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
    }

    @Test(.timeLimit(.minutes(2)))
    func nearNodalBranchesEncloseSpatialDifferentials() throws {
        let exactCurves = try exactCurves(offset: 1.9999)
        #expect(exactCurves.count == 2)
        for exact in exactCurves {
            guard case let .parallelTorusTorus(source) = exact.definition else {
                Issue.record("Expected a near-nodal parallel torus-torus curve.")
                continue
            }
            #expect(source.componentKind == .nearNodalClosedLoop)
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: .first,
                tolerance: tolerance
            )
            #expect(pcurve.hasSpatialDifferentialMagnitudeBounds)
            let bounds = try pcurve.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            let third = try #require(bounds.third)
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
                if isNonC3Join(
                    fraction,
                    componentKind: source.componentKind
                ) {
                    #expect(throws: KernelError.self) {
                        try curve.parameterDerivativesThroughThirdOrder(
                            at: fraction,
                            tolerance: tolerance
                        )
                    }
                } else {
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
    func singularBranchesIntersectLocalTransverseAndTangentPlanes() throws {
        for offset in [2.0, 1.9999] {
            let exact = try #require(try exactCurves(offset: offset).first)
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

    private func isNonC3Join(
        _ sourceFraction: Double,
        componentKind: CertifiedParallelTorusTorusIntersectionCurve.ComponentKind
    ) -> Bool {
        let threshold = Double.ulpOfOne * 1_024.0
        switch componentKind {
        case .regularClosed:
            return false
        case .nodalSelfLoop:
            return abs(sourceFraction) <= threshold
                || abs(sourceFraction - 1.0) <= threshold
        case .nearNodalClosedLoop:
            return abs(sourceFraction) <= threshold
                || abs(sourceFraction - 0.5) <= threshold
                || abs(sourceFraction - 1.0) <= threshold
        }
    }
}
