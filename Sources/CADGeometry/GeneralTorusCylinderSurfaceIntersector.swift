import CADCore

struct GeneralTorusCylinderSurfaceIntersector {
    func intersections(
        torus: CanonicalAnalyticSurface.Torus,
        cylinder: CanonicalAnalyticSurface.Cylinder,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        guard AnalyticAxisRelation.areParallel(
            torus.axis,
            cylinder.axis,
            tolerance: tolerance
        ) == false else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "General torus-cylinder intersection requires non-parallel axes."
            )
        }
        let torusSurface: Surface3D
        let cylinderSurface: Surface3D
        if case .torus = CanonicalAnalyticSurface(firstSurface) {
            torusSurface = firstSurface
            cylinderSurface = secondSurface
        } else {
            torusSurface = secondSurface
            cylinderSurface = firstSurface
        }
        let proceduralCurves = try CertifiedGeneralTorusCylinderIntersectionCurve
            .certifiedCurves(
                torusSurface: torusSurface,
                cylinderSurface: cylinderSurface,
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
        let breaks = (0...32).map { Double($0) / 32.0 }
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
        proceduralCurve: CertifiedGeneralTorusCylinderIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular general torus-cylinder component did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            generalTorusCylinderCurve: proceduralCurve,
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
