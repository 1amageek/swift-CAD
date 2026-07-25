import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedBoundedPlaneConeSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func hyperbolaAndParabolaBoundsEncloseTrimmedDifferentials() throws {
        for exact in try boundedConics() {
            guard case let .boundedPlaneCone(source) = exact.definition else {
                Issue.record("Expected a certified bounded plane-cone curve.")
                continue
            }
            for trim in [
                (start: 0.0, end: 1.0),
                (start: 0.15, end: 0.85),
                (start: 0.85, end: 0.15),
            ] {
                let sourceBounds = try source
                    .spatialDifferentialMagnitudeBounds(
                        fromNormalizedFraction: min(trim.start, trim.end),
                        toNormalizedFraction: max(trim.start, trim.end),
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
                #expect(bounds.second >= sourceBounds.second * scale * scale)

                let lift = SurfaceLiftCurve3D(
                    surface: exact.surface(for: .first),
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                )
                let curve = Curve3D.surfaceLift(lift)
                let interval = try ScalarInterval(
                    lower: 0.2,
                    upper: 0.8
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
    func boundedHyperbolaIntersectsThirdPlaneTransverselyAndTangentially() throws {
        let exact = try #require(try boundedHyperbolas().first)
        let curve = exactCurve(exact)
        let transversePlane = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitY
        ))
        let transverse = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: transversePlane,
            options: .init(),
            tolerance: tolerance
        )
        #expect(transverse.count == 1)
        let transverseIntersection = try #require(transverse.first)
        #expect(transverseIntersection.kind == .transverse)
        #expect(abs(transverseIntersection.point.y) <= tolerance.distance)
        let rangeExcluded = try DefaultCurveSurfaceIntersector()
            .intersections(
                curve: curve,
                surface: transversePlane,
                options: CurveSurfaceIntersectionOptions(
                    curveRange: try ScalarInterval(
                        lower: 0.0,
                        upper: 0.4
                    )
                ),
                tolerance: tolerance
            )
        #expect(rangeExcluded.isEmpty)

        let middle = try curve.point(at: 0.5, tolerance: tolerance)
        let tangentPlane = Surface3D.analytic(.plane(
            origin: middle,
            normal: .unitZ
        ))
        let tangent = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: tangentPlane,
            options: .init(),
            tolerance: tolerance
        )
        #expect(tangent.count == 1)
        let tangentIntersection = try #require(tangent.first)
        #expect(tangentIntersection.kind == .tangent)
        #expect(
            (tangentIntersection.point - middle).length
                <= tolerance.distance
        )
    }

    private func boundedConics()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        try boundedHyperbolas() + boundedParabolas()
    }

    private func boundedHyperbolas()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 6.0
        ))
        return try boundedCurves(
            first: plane,
            second: cone,
            boundaryPoints: [
                hyperbolaPoint(parameter: -0.8, branch: 1.0),
                hyperbolaPoint(parameter: 0.8, branch: 1.0),
                hyperbolaPoint(parameter: -0.5, branch: -1.0),
                hyperbolaPoint(parameter: 0.5, branch: -1.0),
            ]
        )
    }

    private func boundedParabolas()
        throws -> [CertifiedAnalyticAnalyticIntersectionCurve]
    {
        let halfAngle = Double.pi / 6.0
        let normal = try Vector3D(
            x: cos(halfAngle),
            y: 0.0,
            z: -sin(halfAngle)
        ).normalized(tolerance: tolerance.distance)
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(
                x: -normal.x,
                y: -normal.y,
                z: -normal.z
            ),
            normal: normal
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        ))
        return try boundedCurves(
            first: plane,
            second: cone,
            boundaryPoints: [
                parabolaPoint(parameter: -1.0),
                parabolaPoint(parameter: 1.0),
            ]
        )
    }

    private func boundedCurves(
        first: Surface3D,
        second: Surface3D,
        boundaryPoints: [Point3D]
    ) throws -> [CertifiedAnalyticAnalyticIntersectionCurve] {
        let intersections = try #require(
            try DefaultBoundedSurfaceSurfaceIntersector().intersections(
                first: first,
                second: second,
                boundaryPoints: boundaryPoints,
                tolerance: tolerance
            )
        )
        return intersections.compactMap { intersection in
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .boundedPlaneCone = exact.definition else {
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

    private func hyperbolaPoint(
        parameter: Double,
        branch: Double
    ) -> Point3D {
        Point3D(
            x: 1.0,
            y: sinh(parameter),
            z: branch * sqrt(3.0) * cosh(parameter)
        )
    }

    private func parabolaPoint(parameter: Double) -> Point3D {
        Point3D(
            x: sqrt(3.0) * parameter * parameter / 4.0
                - 1.0 / sqrt(3.0),
            y: parameter,
            z: 1.0 + 3.0 * parameter * parameter / 4.0
        )
    }
}
