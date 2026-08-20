import CADCore

struct GeneralConeTorusSurfaceIntersector {
    private let apexContactIntersector = ConeTorusApexContactIntersector()

    func intersections(
        cone: CanonicalAnalyticSurface.Cone,
        torus: CanonicalAnalyticSurface.Torus,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        let axesAreParallel = AnalyticAxisRelation.areParallel(
            cone.axis,
            torus.axis,
            tolerance: tolerance
        )
        let radialOffset = AnalyticAxisRelation.radialOffset(
            from: torus.center,
            axis: torus.axis,
            to: cone.apex
        )
        guard axesAreParallel == false || radialOffset.length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "General cone-torus intersection requires non-coaxial surfaces."
            )
        }
        let coneSurface: Surface3D
        let torusSurface: Surface3D
        if case .cone = CanonicalAnalyticSurface(firstSurface) {
            coneSurface = firstSurface
            torusSurface = secondSurface
        } else {
            coneSurface = secondSurface
            torusSurface = firstSurface
        }
        if let intersections = try apexContactIntersector
            .intersectionsIfApplicable(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                options: options,
                tolerance: tolerance
            ) {
            return intersections
        }
        let proceduralCurves = try CertifiedGeneralConeTorusIntersectionCurve
            .certifiedCurves(
                coneSurface: coneSurface,
                torusSurface: torusSurface,
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
            let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
                generalConeTorusCurve: proceduralCurve,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
            let firstParameterCurve = truth.firstSurfaceParameterCurve
            let secondParameterCurve = truth.secondSurfaceParameterCurve
            let derived = try builder.intersection(
                parameterRange: 0.0...1.0,
                initialBreaks: breaks,
                kind: .transverse,
                firstParameterAt: { fraction in
                    try firstParameterCurve.parameter(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                },
                secondParameterAt: { fraction in
                    try secondParameterCurve.parameter(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                },
                firstParameterDifferentialAt: { fraction in
                    try firstParameterCurve.differentialGeometry(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                },
                secondParameterDifferentialAt: { fraction in
                    try secondParameterCurve.differentialGeometry(
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
                truth: truth,
                tolerance: tolerance
            )
        }
    }

    private func certifiedIntersection(
        _ derived: SurfaceSurfaceIntersection,
        truth: CertifiedAnalyticAnalyticIntersectionCurve,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A regular general cone-torus component did not produce a derived curve cache."
            )
        }
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
