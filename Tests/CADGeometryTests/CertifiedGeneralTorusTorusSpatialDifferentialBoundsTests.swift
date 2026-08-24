import CADCore
@testable import CADGeometry
import Testing

struct CertifiedGeneralTorusTorusSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(2)))
    func certifiedComponentsEncloseTrimmedSpatialDifferentials() throws {
        let exactCurves = try curves()
        #expect(exactCurves.count == 2)

        for exact in exactCurves {
            guard case let .generalTorusTorus(source) = exact.definition else {
                Issue.record("Expected a certified general torus-torus curve.")
                continue
            }
            let sourceBounds = try source.spatialDifferentialMagnitudeBounds(
                tolerance: tolerance
            )
            #expect(sourceBounds.first.isFinite)
            #expect(sourceBounds.second.isFinite)
            #expect(sourceBounds.first > 0.0)
            #expect(sourceBounds.second > 0.0)
            let sourceThird = try #require(sourceBounds.third)
            #expect(sourceThird.isFinite)
            #expect(sourceThird > 0.0)

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
    func certifiedComponentIntersectsLocalTransverseAndTangentPlanes() throws {
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
        let parameter = 0.25
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(lower: 0.249, upper: 0.251),
            maximumSubdivisionDepth: 24
        )
        let localPcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: exact,
            role: .first,
            startFraction: 0.249,
            endFraction: 0.251,
            tolerance: tolerance
        )
        let localBounds = try localPcurve.spatialDifferentialMagnitudeBounds(
            tolerance: tolerance
        )
        #expect(localBounds.first.isFinite)
        #expect(localBounds.second.isFinite)
        #expect(try #require(localBounds.third).isFinite)
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

    @Test(.timeLimit(.minutes(2)))
    func preparedParameterizedChartBoundsEncloseSampledDerivatives() throws {
        for exact in try curves() {
            guard case let .generalTorusTorus(source) = exact.definition else {
                Issue.record("Expected a certified general torus-torus curve.")
                continue
            }
            let role: SurfaceIntersectionSurfaceRole =
                exact.surface(for: .first) == source.parameterizedSurface
                    ? .first
                    : .second
            let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                intersection: exact,
                role: role,
                tolerance: tolerance
            )
            let preparation = try source.prepareSpatialDifferentialBounds(
                tolerance: tolerance
            )
            let parameterPreparation = try pcurve.prepareParameterCellBounds(
                tolerance: tolerance
            )
            let seamCell = try parameterPreparation.bounds(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: 1.0e-8,
                tolerance: tolerance
            )
            #expect(seamCell.usesContinuousLiftForIntegration)

            for interval in [(0.0, 1.0), (0.125, 0.625), (0.75, 0.875)] {
                let bounds = try preparation
                    .parameterizedParameterDifferentialMagnitudeBounds(
                        fromNormalizedFraction: interval.0,
                        toNormalizedFraction: interval.1,
                        tolerance: tolerance
                    )
                for index in 0...32 {
                    let fraction = interval.0
                        + (interval.1 - interval.0) * Double(index) / 32.0
                    let differential = try pcurve.differential(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                    let third = try pcurve.thirdDerivative(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                    let zeroDerivativeNoise = tolerance.relative
                        * max(bounds.uFirst, 1.0)
                    #expect(abs(differential.firstDerivative.x) <= bounds.uFirst)
                    #expect(abs(differential.firstDerivative.y) <= bounds.vFirst)
                    #expect(
                        abs(differential.secondDerivative.x)
                            <= max(bounds.uSecond, zeroDerivativeNoise)
                    )
                    #expect(abs(differential.secondDerivative.y) <= bounds.vSecond)
                    #expect(
                        abs(third.x)
                            <= max(bounds.uThird, zeroDerivativeNoise)
                    )
                    #expect(abs(third.y) <= bounds.vThird)
                }
            }
        }
    }

    private func curves()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let second = Surface3D.analytic(.torus(
            center: Point3D(x: 1.2, y: 0.2, z: 0.5),
            axis: try Vector3D(
                x: 0.25,
                y: 0.1,
                z: 1.0
            ).normalized(tolerance: tolerance.distance),
            majorRadius: 3.4,
            minorRadius: 0.7
        ))
        return try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .generalTorusTorus = exact.definition else {
                return nil
            }
            return exact
        }
    }
}
