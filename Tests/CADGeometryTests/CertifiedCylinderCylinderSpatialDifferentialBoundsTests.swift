import CADCore
@testable import CADGeometry
import Foundation
import Testing

struct CertifiedCylinderCylinderSpatialDifferentialBoundsTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-7,
        angle: 1.0e-8,
        relative: 1.0e-9
    )

    @Test(.timeLimit(.minutes(1)))
    func fullBranchBoundsEncloseTrimmedSpatialDifferentials() throws {
        let parameterizedSurface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitY,
            radius: 1.0
        ))
        let referenceSurface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: try Vector3D(
                x: 0.0,
                y: 1.0,
                z: 1.0
            ).normalized(tolerance: tolerance.distance),
            radius: 4.0
        ))
        let componentKinds:
            [CertifiedCylinderCylinderIntersectionCurve.ComponentKind] = [
                .negativeFullBranch,
                .positiveFullBranch,
            ]
        let trims: [(start: Double, end: Double)] = [
            (start: 0.15, end: 0.85),
            (start: 0.85, end: 0.15),
        ]
        for componentKind in componentKinds {
            let source = try CertifiedCylinderCylinderIntersectionCurve(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                componentKind: componentKind,
                lowerAngle: 0.0,
                upperAngle: 2.0 * Double.pi,
                tolerance: tolerance
            )
            let sourceBounds = try source
                .fullBranchSpatialDifferentialMagnitudeBounds(
                    tolerance: tolerance
                )
            let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
                cylinderCylinderCurve: source,
                firstSurface: parameterizedSurface,
                secondSurface: referenceSurface,
                tolerance: tolerance
            )
            for trim in trims {
                let pcurve = try CertifiedAnalyticPairSurfaceParameterCurve(
                    intersection: truth,
                    role: .first,
                    startFraction: trim.start,
                    endFraction: trim.end,
                    tolerance: tolerance
                )
                let pcurveBounds = try pcurve
                    .fullBranchCylinderSpatialDifferentialMagnitudeBounds(
                        tolerance: tolerance
                    )
                let scale = pcurve.endFraction - pcurve.startFraction
                #expect(
                    pcurveBounds.first
                        >= sourceBounds.first * abs(scale)
                )
                #expect(
                    pcurveBounds.second
                        >= sourceBounds.second * scale * scale
                )

                let lift = SurfaceLiftCurve3D(
                    surface: parameterizedSurface,
                    parameterCurve: .certifiedAnalyticPair(pcurve)
                )
                let curve = Curve3D.surfaceLift(lift)
                let interval = try ScalarInterval(lower: 0.2, upper: 0.8)
                let optionalCertifiedSecond =
                    try SurfaceLiftDifferentialBounder()
                        .secondDerivativeMagnitude(
                            lift: lift,
                            interval: interval,
                            tolerance: tolerance
                        )
                let certifiedSecond = try #require(
                    optionalCertifiedSecond
                )
                for index in 0...128 {
                    let fraction = interval.lower
                        + interval.width * Double(index) / 128.0
                    let geometry = try curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    #expect(
                        geometry.firstDerivative.length
                            <= pcurveBounds.first
                    )
                    #expect(
                        geometry.secondDerivative.length
                            <= pcurveBounds.second
                    )
                    #expect(
                        geometry.secondDerivative.length
                            <= certifiedSecond
                    )
                }
            }
        }
    }
}
