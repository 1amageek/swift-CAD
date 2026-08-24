import CADCore

/// Resolves the non-regular graph created when a sphere contains a cone apex.
///
/// The cone quadratic has one parameter-space root that maps every cone angle
/// to the same apex. This intersector removes that constant root and certifies
/// the remaining geometric root as either a separate loop or apex-bounded
/// graph edges.
struct SphereConeApexContactIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersectionsIfApplicable(
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        guard let topology = try CertifiedSphereConeIntersectionCurve
            .apexContactTopology(
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                tolerance: tolerance
            ) else {
            return nil
        }
        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        let ranges: [ClosedRange<Double>]
        let hasIsolatedApex: Bool
        switch topology {
        case .isolatedPointAndLoop:
            ranges = [0.0...(2.0 * Double.pi)]
            hasIsolatedApex = true
        case let .nodeIntervals(intervals):
            ranges = intervals
            hasIsolatedApex = false
        }

        var result: [SurfaceSurfaceIntersection] = []
        result.reserveCapacity(ranges.count + (hasIsolatedApex ? 1 : 0))
        for range in ranges {
            result.append(try intersection(
                range: range,
                isClosed: hasIsolatedApex,
                builder: builder,
                sphereSurface: sphereSurface,
                coneSurface: coneSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            ))
        }
        if hasIsolatedApex {
            guard case let .cone(cone) = CanonicalAnalyticSurface(coneSurface) else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A sphere-cone apex resolver requires an analytic cone."
                )
            }
            result.append(try verifier.point(
                cone.apex,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            ))
        }
        return result
    }

    private func intersection(
        range: ClosedRange<Double>,
        isClosed: Bool,
        builder: SurfaceIntersectionSplineBuilder,
        sphereSurface: Surface3D,
        coneSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let proceduralCurve = try CertifiedSphereConeIntersectionCurve(
            sphereSurface: sphereSurface,
            coneSurface: coneSurface,
            componentKind: .apexReducedAngularInterval,
            lowerAngle: range.lowerBound,
            upperAngle: range.upperBound,
            tolerance: tolerance
        )
        let evaluationContext = SurfaceIntersectionCurveEvaluationContext(
            curve: proceduralCurve,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let derived = try builder.intersection(
            parameterRange: 0.0...1.0,
            initialBreaks: (0...16).map { Double($0) / 16.0 },
            kind: .mixed,
            isClosed: isClosed,
            firstParameterAt: { fraction in
                try evaluationContext.firstParameter(at: fraction)
            },
            secondParameterAt: { fraction in
                try evaluationContext.secondParameter(at: fraction)
            },
            pointAt: { fraction in
                try evaluationContext.point(at: fraction)
            }
        )
        guard case let .curve(derivedCurve) = derived else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A sphere-cone apex graph edge did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            sphereConeCurve: proceduralCurve,
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
