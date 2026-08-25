import CADCore
import CADGeometry
import CADTopology

struct ExactImplicitIntersectionTransferSource: Sendable {
    let curve: CertifiedImplicitIntersectionCurve
    let firstSurface: Surface3D
    let secondSurface: Surface3D
    let firstParameterCurve: SurfaceParameterCurve
    let secondParameterCurve: SurfaceParameterCurve

    static func resolve(
        edgeID: EdgeID,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> ExactImplicitIntersectionTransferSource {
        var implicit: CertifiedImplicitIntersectionCurve?
        var analyticImplicit: CertifiedAnalyticBSplineIntersectionCurve?
        for face in model.faces.values {
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw KernelError(
                        phase: .exchange,
                        code: .missingReference,
                        tolerance: tolerance,
                        message: "Implicit intersection transfer references a missing face loop."
                    )
                }
                for coedge in loop.coedges where coedge.edgeID == edgeID {
                    switch untranslatedBase(coedge.surfaceParameterCurve) {
                    case let .certifiedImplicit(curve):
                        implicit = curve.intersection
                    case let .certifiedAnalyticImplicit(curve):
                        analyticImplicit = curve.intersection
                    case .affine, .constantU, .constantV, .harmonic,
                         .sphericalGreatCircle, .polyline, .bSpline,
                         .certifiedAnalyticPair, .projectedAnalytic,
                         .rigidImage, .offsetSurfaceImage, nil:
                        continue
                    case .periodicTranslation:
                        continue
                    }
                }
            }
        }
        if let analyticImplicit {
            let bounded = Surface3D.bSpline(analyticImplicit.boundedSurface)
            return ExactImplicitIntersectionTransferSource(
                curve: analyticImplicit.implicitCurve,
                firstSurface: analyticImplicit.analyticIsFirst
                    ? analyticImplicit.analyticSurface
                    : bounded,
                secondSurface: analyticImplicit.analyticIsFirst
                    ? bounded
                    : analyticImplicit.analyticSurface,
                firstParameterCurve: analyticImplicit.firstSurfaceParameterCurve,
                secondParameterCurve: analyticImplicit.secondSurfaceParameterCurve
            )
        }
        guard let implicit else {
            throw KernelError(
                phase: .exchange,
                code: .missingReference,
                tolerance: tolerance,
                message: "An implicit intersection edge requires certified face-local pcurve provenance."
            )
        }
        return ExactImplicitIntersectionTransferSource(
            curve: implicit,
            firstSurface: .bSpline(implicit.firstSurface),
            secondSurface: .bSpline(implicit.secondSurface),
            firstParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: implicit,
                    role: .first,
                    tolerance: tolerance
                )
            ),
            secondParameterCurve: .certifiedImplicit(
                try CertifiedImplicitSurfaceParameterCurve(
                    intersection: implicit,
                    role: .second,
                    tolerance: tolerance
                )
            )
        )
    }

    private static func untranslatedBase(
        _ curve: SurfaceParameterCurve?
    ) -> SurfaceParameterCurve? {
        guard case let .periodicTranslation(base, _, _) = curve else {
            return curve
        }
        return untranslatedBase(base)
    }
}

struct ExactImplicitIntersectionTransferBuilder {
    struct Result: Sendable {
        let curve: BSplineCurve3D
        let firstPcurve: SurfaceParameterCurve
        let secondPcurve: SurfaceParameterCurve
        let maximumResidualUpperBound: Double
    }

    func build(
        source: ExactImplicitIntersectionTransferSource,
        trim: CurveTrim,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        try source.curve.validate(tolerance: tolerance)
        let lower = min(trim.startParameter, trim.endParameter)
        let upper = max(trim.startParameter, trim.endParameter)
        guard lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > tolerance.relative else {
            throw KernelError(
                phase: .exchange,
                code: .invalidInput,
                residual: upper - lower,
                tolerance: tolerance,
                message: "An implicit intersection transfer requires a non-degenerate normalized trim interval."
            )
        }
        var breaks = [lower, upper]
        let cellCount = source.curve.cells.count
        for index in 1..<cellCount {
            let fraction = Double(index) / Double(cellCount)
            if fraction > lower + tolerance.relative,
               fraction < upper - tolerance.relative {
                breaks.append(fraction)
            }
        }
        let start = try source.curve.point(
            atNormalizedFraction: lower,
            tolerance: tolerance
        )
        let end = try source.curve.point(
            atNormalizedFraction: upper,
            tolerance: tolerance
        )
        let isClosed = source.curve.isClosed
            && lower <= tolerance.relative
            && upper >= 1.0 - tolerance.relative
            && start.isApproximatelyEqual(to: end, tolerance: tolerance.distance)
        let intersection = try SurfaceIntersectionSplineBuilder(
            firstSurface: source.firstSurface,
            secondSurface: source.secondSurface,
            options: SurfaceSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 20,
                maximumSeedCount: 8_192
            ),
            maximumAcceptedResidual: tolerance.distance,
            tolerance: tolerance
        ).intersection(
            parameterRange: lower...upper,
            initialBreaks: breaks,
            kind: .transverse,
            isClosed: isClosed,
            firstParameterAt: { parameter in
                try source.firstParameterCurve.parameter(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                )
            },
            secondParameterAt: { parameter in
                try source.secondParameterCurve.parameter(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                )
            },
            pointAt: { parameter in
                try source.curve.point(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                )
            }
        )
        guard case let .curve(transferred) = intersection,
              case let .bSpline(bSpline) = transferred.derivedRepresentation.curve else {
            throw KernelError(
                phase: .exchange,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "Implicit intersection transfer did not produce a verified rational spline representation."
            )
        }
        return Result(
            curve: bSpline,
            firstPcurve: transferred.derivedRepresentation.firstSurfaceParameterCurve,
            secondPcurve: transferred.derivedRepresentation.secondSurfaceParameterCurve,
            maximumResidualUpperBound: transferred.maximumResidual
        )
    }
}
