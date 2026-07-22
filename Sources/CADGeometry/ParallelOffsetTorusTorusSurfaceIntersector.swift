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
            let derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: breaks,
                kind: .transverse,
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
                message: "A regular parallel torus-torus component did not produce a derived curve cache."
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
