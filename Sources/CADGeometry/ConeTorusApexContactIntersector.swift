import CADCore

/// Resolves cone-apex contact with a torus through the factored generator
/// cubic. This pair-specific layer classifies apex nodes and generator folds;
/// the bounded B-spline intersector remains responsible only for general
/// rational surface pairs.
struct ConeTorusApexContactIntersector {
    func intersectionsIfApplicable(
        coneSurface: Surface3D,
        torusSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        try options.validate(tolerance: tolerance)
        guard case let .cone(cone) = CanonicalAnalyticSurface(coneSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-torus apex resolver requires an analytic cone."
            )
        }
        let apexProjection: SurfaceParameterProjection
        do {
            apexProjection = try torusSurface.parameterProjection(
                of: cone.apex,
                tolerance: tolerance
            )
        } catch let error as KernelError where error.code == .intersectionFailure {
            return nil
        }
        guard apexProjection.residual <= tolerance.distance else {
            return nil
        }

        let apexCurves = try CertifiedConeTorusApexIntersectionCurve
            .certifiedCurves(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                tolerance: tolerance
            )
        return try apexCurves.enumerated().map { index, apexCurve in
            let proceduralCurve = try CertifiedGeneralConeTorusIntersectionCurve(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                branchIndex: index,
                branchCount: apexCurves.count,
                apexReduction: apexCurve,
                maximumSubdivisionDepth: min(options.maximumSubdivisionDepth, 24),
                maximumCellCount: min(options.maximumSubdivisionCells, 65_536),
                tolerance: tolerance
            )
            let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
                generalConeTorusCurve: proceduralCurve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
            let point = try truth.point(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let firstParameter = try truth.internalParameter(
                for: .first,
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let secondParameter = try truth.internalParameter(
                for: .second,
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            return .curve(try SurfaceSurfaceIntersectionCurve(
                truth: .analyticAnalytic(truth),
                derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                    curve: truth.curve,
                    firstSurfaceParameterCurve: truth.firstSurfaceParameterCurve,
                    secondSurfaceParameterCurve: truth.secondSurfaceParameterCurve,
                    maximumResidualUpperBound: apexCurve.maximumResidualUpperBound,
                    tolerance: tolerance
                ),
                kind: .mixed,
                firstSurfaceAnchor: try SurfaceParameterProjection(
                    u: firstParameter.u,
                    v: firstParameter.v,
                    point: point,
                    residual: 0.0
                ),
                secondSurfaceAnchor: try SurfaceParameterProjection(
                    u: secondParameter.u,
                    v: secondParameter.v,
                    point: point,
                    residual: 0.0
                ),
                tolerance: tolerance
            ))
        }
    }
}
