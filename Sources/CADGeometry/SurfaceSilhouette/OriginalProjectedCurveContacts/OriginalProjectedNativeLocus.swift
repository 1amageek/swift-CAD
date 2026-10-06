import CADCore

/// Retains generic quotient fibers and complete UV source coverage for projected overlap lifting.
struct OriginalProjectedNativeLocus: Sendable {
    let original: OriginalProjectedNativePolynomialPair
    let sharedLocus: ExactBivariatePolynomial
    let fibers: ExactSurfaceLocusCommonFiber
    let branchProjections: [OriginalProjectedNativeBranchProjection]
    let parameterProjections: [ExactSurfaceLocusParameterProjection]
    let parameterPlaneProjections: [OriginalRationalPlaneCurveProjection]
    let parameterStationFibers: [OriginalProjectedNativeSectionFiber]
    let exceptionalUVFibers: [OriginalProjectedNativeFiber]
    let selectedStationContacts: [OriginalProjectedNativeSectionContact]
    let projection: OriginalRationalPlaneCurveProjection
    let remainingIsolatedUV: [ExactBivariateSystemRoot]

    init(original: OriginalProjectedNativePolynomialPair,
        domain: SurfaceParameterBox, usage: inout SurfaceSilhouetteUsage) throws {
        var shared = original.zeroLaw
        let gcd = ExactBivariateGCD()
        if let eliminated = original.eliminated {
            shared = try gcd.greatestCommonDivisor(shared, eliminated, usage: &usage)
        } else {
            if let horizontal = original.horizontal.coefficients.first {
                shared = try gcd.greatestCommonDivisor(shared, horizontal, usage: &usage)
            }
            if let vertical = original.vertical.coefficients.first {
                shared = try gcd.greatestCommonDivisor(shared, vertical, usage: &usage)
            }
        }
        guard shared.uDegree > 0 || shared.vDegree > 0 else {
            throw rationalAlgebraFailure("Projected positive incidence has no original common locus.")
        }
        self.original = original; sharedLocus = shared
        fibers = try .init(locus: shared, horizontal: original.horizontal,
            vertical: original.vertical, usage: &usage)
        var parameters: [ExactSurfaceLocusParameterProjection] = []
        var branchEvents: [OriginalProjectedNativeBranchProjection] = []
        let freeAlongU = original.silhouette.original.freeCoordinate == .u
        let traversal = try original.silhouette.original.originalTrimGraphAuthority()
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
        let trimValues = [try SurfaceSilhouetteProjectedTraversalBounds.nativeFree(original.silhouette.lower.original,
            authority: traversal, alongU: freeAlongU, usage: &usage),
            try SurfaceSilhouetteProjectedTraversalBounds.nativeFree(original.silhouette.upper.original,
                authority: traversal, alongU: freeAlongU, usage: &usage)]
        for component in fibers.components {
            for reduced in try ExactSurfaceLocusCommonFiber.squareFreeParameters(component: component, usage: &usage) {
                try RationalAlgebraStorage.retain(1, of: OriginalProjectedNativeBranchProjection.self, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: ExactSurfaceLocusParameterProjection.self, usage: &usage)
                branchEvents.append(try .init(component: reduced, domain: domain, edgeRange: original.edgeRange,
                    freeAlongU: freeAlongU, originalTrimFreeValues: trimValues, usage: &usage))
                parameters.append(try .init(component: reduced, usage: &usage))
            }
        }
        branchProjections = branchEvents
        parameterProjections = parameters
        var planeProjections: [OriginalRationalPlaneCurveProjection] = []
        var stationFibers: [OriginalProjectedNativeSectionFiber] = []
        let parameterDomain = try SurfaceParameterBox(u: domain.u, v: original.edgeRange)
        for parameterIndex in parameters.indices {
            let parameter = parameters[parameterIndex]
            let events = branchEvents[parameterIndex]
            switch parameter.kind {
            case .wholeParameterFiber, .noGenericFiber: break
            case .coordinateSystem(let locus, let common):
                try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
                for station in try ExactBivariateSystemSolver.isolatedRoots(of: [locus, common],
                    over: parameterDomain, maximumDepth: usage.maximumDepth, usage: &usage) {
                    let fiber = try OriginalProjectedNativeSectionFiber(original: original,
                        locus: parameter.component.originalLocus, at: station, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: OriginalProjectedNativeSectionFiber.self, usage: &usage)
                    stationFibers.append(fiber)
                }
            case .projected(let polynomial):
                guard !polynomial.isZero else {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): Actual projected native
                    // section preparation must cover a nullified transverse resultant
                    // without dropping its original real fibers or publishing empty.
                    throw rationalAlgebraFailure("Original common section has a nullified parameter projection.")
                }
                let zero = try OriginalRationalZeroSetAuthority(original: polynomial, usage: &usage)
                let projection = try OriginalRationalPlaneCurveProjection(original: zero,
                    over: parameterDomain, maximumDepth: usage.maximumDepth, usage: &usage)
                try RationalAlgebraStorage.retain(1, of: OriginalRationalPlaneCurveProjection.self, usage: &usage)
                planeProjections.append(projection)
                if events.freeAlongU, events.projection.uDegree > 0 {
                    try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
                    for station in try ExactBivariateSystemSolver.isolatedRoots(of: [polynomial, events.projection],
                        over: parameterDomain, maximumDepth: usage.maximumDepth, usage: &usage) {
                        let fiber = try OriginalProjectedNativeSectionFiber(original: original,
                            locus: parameter.component.originalLocus, at: station, usage: &usage)
                        try RationalAlgebraStorage.retain(1, of: OriginalProjectedNativeSectionFiber.self, usage: &usage)
                        stationFibers.append(fiber)
                    }
                }
                for station in projection.stations {
                    for root in station.roots {
                        let fiber = try OriginalProjectedNativeSectionFiber(original: original,
                            locus: parameter.component.originalLocus, at: root, usage: &usage)
                        try RationalAlgebraStorage.retain(1, of: OriginalProjectedNativeSectionFiber.self, usage: &usage)
                        stationFibers.append(fiber)
                    }
                }
            }
        }
        parameterPlaneProjections = planeProjections; parameterStationFibers = stationFibers
        var selected: [OriginalProjectedNativeSectionContact] = []
        for fiber in stationFibers {
            for point in fiber.points {
                let parameters = try original.silhouette.original.projectedOriginalParameters(
                    originalU: point.originalU, originalV: point.originalV, usage: &usage)
                for parameterIndex in parameters.indices {
            let parameter = parameters[parameterIndex]
            let events = branchEvents[parameterIndex]
                    try RationalAlgebraStorage.retain(2, of: SurfaceSilhouetteTrimEndpoint.self, usage: &usage)
                    let edge = SurfaceSilhouetteTrimEndpoint(point.originalEdgeParameter,
                        depth: point.originalEdgeParameter.context.depth)
                    let silhouette = SurfaceSilhouetteTrimEndpoint(parameter, depth: parameter.context.depth)
                    if try silhouette.compare(to: original.silhouette.lower, usage: &usage) < 0 { continue }
                    if try silhouette.compare(to: original.silhouette.upper, usage: &usage) > 0 { continue }
                    try RationalAlgebraStorage.retain(1, of: OriginalProjectedNativeSectionContact.self, usage: &usage)
                    selected.append(.init(edgeParameter: edge, silhouetteParameter: silhouette,
                        originalPoint: point, originalProjection: fiber.sourceProjection))
                }
            }
        }
        selectedStationContacts = selected
        var exceptionFibers: [OriginalProjectedNativeFiber] = []
        for component in fibers.components {
            for exception in component.exceptionalCoefficients {
                if exception.uDegree <= 0, exception.vDegree <= 0 { continue }
                try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
                for station in try ExactBivariateSystemSolver.isolatedRoots(
                    of: [component.originalLocus, exception], over: domain,
                    maximumDepth: usage.maximumDepth, usage: &usage) {
                    let fiber = try OriginalProjectedNativeFiber(original: original, at: station, usage: &usage)
                    try RationalAlgebraStorage.retain(1, of: OriginalProjectedNativeFiber.self, usage: &usage)
                    exceptionFibers.append(fiber)
                }
            }
        }
        exceptionalUVFibers = exceptionFibers
        let authority = try OriginalRationalZeroSetAuthority(original: shared, usage: &usage)
        projection = try .init(original: authority, over: domain,
            maximumDepth: usage.maximumDepth, usage: &usage)
        if let eliminated = original.eliminated, !eliminated.isZero {
            let first = try original.zeroLaw.dividedExactly(by: shared, usage: &usage)
            let second = try eliminated.dividedExactly(by: shared, usage: &usage)
            try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
            remainingIsolatedUV = try ExactBivariateSystemSolver.isolatedRoots(of: [first, second],
                over: domain, maximumDepth: usage.maximumDepth, usage: &usage)
        } else { remainingIsolatedUV = [] }
    }
}
