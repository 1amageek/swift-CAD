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
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "The analytic-pair intersector has no exact closed-form implementation for this surface pair."
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
        return .curve(try SurfaceSurfaceIntersectionCurve(
            truth: .analyticAnalytic(truth),
            derivedRepresentation: try SurfaceSurfaceIntersectionDerivedRepresentation(
                curve: truth.curve,
                firstSurfaceParameterCurve: firstPcurve,
                secondSurfaceParameterCurve: secondPcurve,
                maximumResidualUpperBound: truth.maximumResidualUpperBound,
                tolerance: tolerance
            ),
            kind: .transverse,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            tolerance: tolerance
        ))
    }
}
