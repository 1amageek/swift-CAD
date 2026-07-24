import CADCore

struct ParallelOffsetTorusTorusSurfaceIntersector {
    func intersections(
        first: CanonicalAnalyticSurface.Torus,
        second: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        guard AnalyticAxisRelation.areParallel(
            first.axis,
            second.axis,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: first.axis.cross(second.axis).length,
                tolerance: tolerance,
                message: "Offset torus-torus intersection requires parallel axes."
            )
        }
        let proceduralCurves = try CertifiedParallelTorusTorusIntersectionCurve
            .certifiedCurves(
                firstTorusSurface: firstSurface,
                secondTorusSurface: secondSurface,
                options: options,
                tolerance: tolerance
            )
        guard proceduralCurves.isEmpty == false else { return [] }
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        let segmentCount = min(16, max(1, options.maximumSeedCount))
        let breaks = (0...segmentCount).map {
            Double($0) / Double(segmentCount)
        }
        return try proceduralCurves.map { proceduralCurve in
            if proceduralCurve.componentKind == .nearNodalClosedLoop {
                return try exactIntersection(
                    proceduralCurve: proceduralCurve,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                )
            }
            let kind: CurveSurfaceIntersectionKind =
                proceduralCurve.componentKind == .nodalSelfLoop
                    ? .mixed
                    : .transverse
            let derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: breaks,
                kind: kind,
                isClosed: proceduralCurve.componentKind == .regularClosed,
                firstParameterAt: { fraction in
                    try proceduralCurve.parameter(
                        on: firstSurface,
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                },
                secondParameterAt: { fraction in
                    try proceduralCurve.parameter(
                        on: secondSurface,
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                },
                pointAt: { fraction in
                    try proceduralCurve.point(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                }
            )
            return try certifiedIntersection(
                derived,
                proceduralCurve: proceduralCurve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
    }

    private func exactIntersection(
        proceduralCurve: CertifiedParallelTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            parallelTorusTorusCurve: proceduralCurve,
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
                maximumResidualUpperBound:
                    proceduralCurve.maximumResidualUpperBound,
                tolerance: tolerance
            ),
            kind: .mixed,
            firstSurfaceAnchor: try SurfaceParameterProjection(
                u: firstParameter.u,
                v: firstParameter.v,
                point: point,
                residual: proceduralCurve.maximumResidualUpperBound
            ),
            secondSurfaceAnchor: try SurfaceParameterProjection(
                u: secondParameter.u,
                v: secondParameter.v,
                point: point,
                residual: proceduralCurve.maximumResidualUpperBound
            ),
            tolerance: tolerance
        ))
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        proceduralCurve: CertifiedParallelTorusTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A certified parallel torus-torus component did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            parallelTorusTorusCurve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: derivedCurve.derivedRepresentation,
            kind: derivedCurve.kind,
            firstSurfaceAnchor: derivedCurve.firstSurfaceAnchor,
            secondSurfaceAnchor: derivedCurve.secondSurfaceAnchor,
            tolerance: tolerance
        ))
    }
}
