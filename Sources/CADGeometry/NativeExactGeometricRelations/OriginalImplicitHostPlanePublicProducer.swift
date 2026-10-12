import CADCore

/// Publishes checked whole-host exclusion with the original caller's allowance.
struct OriginalImplicitHostPlanePublicProducer {
    private typealias Base = OriginalExactScalarDomain
    private typealias Admission = NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    private typealias Interval = ExactParameterInterval<Base.Value>

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil)
        throws -> CurveSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): This ordinary implicit exclusion route
        // admits only the source-owned constant-height bilinear Native host capability.
        // Other original implicit host/target laws need whole-support authority before
        // their empty numerical arrays can count as complete original results.
        guard OriginalImplicitHostExclusionSnapshotProvider.supports(curve: curve, plane: surface) else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
            let depth = usage.maximumAlgebraicDepth
            var a = Admission(usage: usage, maximumDepth: depth)
            try a.checkpoint(); try invocation?.consume(depth: 0)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth: invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts = min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells, options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: depth, maximumCharts: charts, maximumFamilies: 0, maximumIdentityProofs: 0)
            let field = try Base(maximumValueDepth: depth, maximumCoefficientDepth: depth, using: &a)
            let source = try DefaultOriginalSourceBindingIssuer(
                provider: OriginalImplicitHostExclusionSnapshotProvider(tolerance: tolerance))
                .bind(curve, limits: sourceLimits, using: &a)
            let target = try DefaultOriginalSourceBindingIssuer(provider: OriginalPlaneSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            let one = try field.integer(1, using: &a)
            let basis = try DefaultOriginalPlaneBasisIssuer<OriginalPlaneSnapshot, Base>()
                .issue(source: target, field: field, firstLength: one, normalLength: one, limits: sourceLimits, using: &a)
            let exclusion = try DefaultOriginalImplicitHostPlaneSeparationIssuer()
                .issue(source: source, plane: basis, maximumCells: charts, limits: sourceLimits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Interval.self))
            let curveIntervals: [Interval]
            if let range = options.curveRange {
                curveIntervals = [try interval(range, field: field, using: &a)]
            } else {
                curveIntervals = [try .checked(field: field,
                    lower: .finite(exclusion.support.lower), upper: .finite(exclusion.support.upper),
                    depth: exclusion.proofDepth, using: &a)]
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: [Interval].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: Interval.self))
            let planeIntervals = [[try interval(options.surfaceURange, field: field, using: &a)],
                [try interval(options.surfaceVRange, field: field, using: &a)]]
            let original = try OriginalImplicitHostPlaneExclusion.resolve(exclusion: exclusion,
                curveIntervals: curveIntervals, planeIntervals: planeIntervals, limits: limits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: [], overlaps: [], originalImplicitHostPlaneExclusion: original)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }

    private func interval(_ range: ScalarInterval?, field: Base, using a: inout Admission) throws -> Interval {
        let depth = try ExactScalarDepth(value: 0, coefficient: 0)
        guard let range else {
            return try .checked(field: field, lower: .negativeInfinity, upper: .positiveInfinity, depth: depth, using: &a)
        }
        return try .checked(field: field, lower: .finite(field.binary64(exactly: range.lower, using: &a)),
            upper: .finite(field.binary64(exactly: range.upper, using: &a)), depth: depth, using: &a)
    }
}
