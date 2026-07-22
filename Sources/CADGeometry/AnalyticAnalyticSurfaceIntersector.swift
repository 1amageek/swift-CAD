import CADCore

struct AnalyticAnalyticSurfaceIntersector {
    func intersections(
        first: Surface3D,
        second: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try options.validate(tolerance: tolerance)
        try first.validate(tolerance: tolerance)
        try second.validate(tolerance: tolerance)

        let firstCanonical = CanonicalAnalyticSurface(first)
        let secondCanonical = CanonicalAnalyticSurface(second)
        let planeSurface: Surface3D
        let torusSurface: Surface3D
        switch (firstCanonical, secondCanonical) {
        case (.plane, .torus):
            planeSurface = first
            torusSurface = second
        case (.torus, .plane):
            planeSurface = second
            torusSurface = first
        default:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The plane-torus analytic-pair intersector received a different surface pair."
            )
        }

        let components = try CertifiedPlaneTorusIntersectionCurve.regularComponents(
            planeSurface: planeSurface,
            torusSurface: torusSurface,
            options: options,
            tolerance: tolerance
        )
        return try components.map { component in
            try intersection(
                component: component,
                first: first,
                second: second,
                tolerance: tolerance
            )
        }
    }

    private func intersection(
        component: CertifiedPlaneTorusIntersectionCurve,
        first: Surface3D,
        second: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            planeTorusCurve: component,
            firstSurface: first,
            secondSurface: second,
            tolerance: tolerance
        )
        let point = try truth.point(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let firstAnchor = try first.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let secondAnchor = try second.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let firstPcurve = truth.firstSurfaceParameterCurve
        let secondPcurve = truth.secondSurfaceParameterCurve
        try firstPcurve.validate(on: first, tolerance: tolerance)
        try secondPcurve.validate(on: second, tolerance: tolerance)
        let kind: CurveSurfaceIntersectionKind
        switch component.componentKind {
        case .negativeInnerTangencyBranch, .positiveInnerTangencyBranch:
            kind = .mixed
        case .negativeFullBranch, .positiveFullBranch, .boundedMinorAngle:
            kind = .transverse
        }
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: truth.curve,
                firstSurfaceParameterCurve: firstPcurve,
                secondSurfaceParameterCurve: secondPcurve,
                maximumResidualUpperBound: truth.maximumResidualUpperBound,
                tolerance: tolerance
            ),
            kind: kind,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            tolerance: tolerance
        ))
    }
}
