import Foundation
import CADCore
import CADGeometry
import CADTopology

struct ExactPlaneTorusTransferBuilder {
    struct Result: Sendable {
        let curve: BSplineCurve3D
        let planePcurve: SurfaceParameterCurve
        let torusPcurve: SurfaceParameterCurve
        let maximumResidualUpperBound: Double
    }

    func build(
        curve: CertifiedPlaneTorusIntersectionCurve,
        trim: CurveTrim,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        try curve.validate(tolerance: tolerance)
        let lower = min(trim.startParameter, trim.endParameter)
        let upper = max(trim.startParameter, trim.endParameter)
        let span = upper - lower
        guard span > tolerance.angle,
              span <= 2.0 * Double.pi + tolerance.angle,
              try Curve3D.analytic(.planeTorus(curve)).parameterDomain.containsSpan(
                  from: trim.startParameter,
                  to: trim.endParameter,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .exchange,
                code: .invalidInput,
                residual: span,
                tolerance: tolerance,
                message: "A plane-torus transfer edge must span a finite interval of at most one period."
            )
        }
        let segmentCount = max(16, Int(ceil(span / (Double.pi / 8.0))))
        let breaks = (0...segmentCount).map { index in
            lower + span * Double(index) / Double(segmentCount)
        }
        let start = try curve.point(at: lower, tolerance: tolerance)
        let end = try curve.point(at: upper, tolerance: tolerance)
        let isClosed = abs(span - 2.0 * Double.pi) <= tolerance.angle
            && start.isApproximatelyEqual(to: end, tolerance: tolerance.distance)
        let intersection = try SurfaceIntersectionSplineBuilder(
            firstSurface: curve.planeSurface,
            secondSurface: curve.torusSurface,
            options: SurfaceSurfaceIntersectionOptions(),
            tolerance: tolerance
        ).intersection(
            parameterRange: lower...upper,
            initialBreaks: breaks,
            kind: .transverse,
            isClosed: isClosed,
            pointAt: { parameter in
                try curve.point(at: parameter, tolerance: tolerance)
            }
        )
        guard case let .curve(transferred) = intersection,
              case let .bSpline(bSpline) = transferred.derivedRepresentation.curve else {
            throw KernelError(
                phase: .exchange,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Plane-torus transfer did not produce a verified rational spline representation."
            )
        }
        return Result(
            curve: bSpline,
            planePcurve: transferred.derivedRepresentation.firstSurfaceParameterCurve,
            torusPcurve: transferred.derivedRepresentation.secondSurfaceParameterCurve,
            maximumResidualUpperBound: transferred.maximumResidual
        )
    }
}
