import CADCore

/// Resolves the non-regular graph created when one cone apex lies on another
/// cone.
///
/// The ruling quadratic has a constant parameter-space root that maps every
/// angle to the same apex. This intersector removes that root and certifies the
/// remaining geometric root independently.
struct ConeConeApexContactIntersector {
    private let verifier = SurfaceSurfaceIntersectionVerifier()

    func intersectionsIfApplicable(
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection]? {
        guard let topology = try CertifiedConeConeIntersectionCurve
            .apexContactTopology(
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                tolerance: tolerance
            ) else {
            return nil
        }
        guard case let .cone(parameterizedCone) = CanonicalAnalyticSurface(
            parameterizedSurface
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A cone-cone apex resolver requires two analytic cones."
            )
        }

        let ranges: [ClosedRange<Double>]
        let hasIsolatedApex: Bool
        let hasClosedLoop: Bool
        switch topology {
        case .isolatedPoint:
            ranges = []
            hasIsolatedApex = true
            hasClosedLoop = false
        case .isolatedPointAndLoop:
            ranges = [0.0...(2.0 * Double.pi)]
            hasIsolatedApex = true
            hasClosedLoop = true
        case let .nodeIntervals(intervals):
            ranges = intervals
            hasIsolatedApex = false
            hasClosedLoop = false
        }

        let builder = SurfaceIntersectionSplineBuilder(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            options: options,
            tolerance: tolerance
        )
        var result: [SurfaceSurfaceIntersection] = []
        result.reserveCapacity(ranges.count + (hasIsolatedApex ? 1 : 0))
        for range in ranges {
            result.append(try intersection(
                range: range,
                isClosed: hasClosedLoop,
                builder: builder,
                referenceSurface: referenceSurface,
                parameterizedSurface: parameterizedSurface,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            ))
        }
        if hasIsolatedApex {
            result.append(try verifier.point(
                parameterizedCone.apex,
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
        referenceSurface: Surface3D,
        parameterizedSurface: Surface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        let proceduralCurve = try CertifiedConeConeIntersectionCurve(
            referenceSurface: referenceSurface,
            parameterizedSurface: parameterizedSurface,
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
                message: "A cone-cone apex graph edge did not produce a derived curve cache."
            )
        }
        let truth = try CertifiedAnalyticAnalyticIntersectionCurve(
            coneConeCurve: proceduralCurve,
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
