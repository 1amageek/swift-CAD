import CADCore

/// Publishes complete original contacts before the unconverted numerical reducer.
struct OriginalCertifiedConeConePublicProducer {
    private typealias Admission = NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil) throws -> CurveSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): This ordinary/callback public route owns
        // only the two declared full branches of the frozen cardinal cone pair and
        // planeX0/uZ. Other targets/branches need complete original source/UV owners
        // before their existing numerical reducer can count as exact acceptance.
        guard OriginalCertifiedConeConeFullSnapshotProvider.supports(curve),
            OriginalCertifiedConeConeTargetSnapshotProvider.supports(surface),
            case .certifiedIntersection(.coneCone(let original)) = curve,
            case .analytic(.cone(_, _, let alpha)) = original.referenceSurface,
            case .analytic(.cone(_, _, let beta)) = original.parameterizedSurface else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
            var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
            try a.checkpoint(); try invocation?.consume(depth: 0)
            let sourceLimits = try OriginalSourceIssuanceLimits(remainingSourceDepth:
                invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts = min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells, options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: usage.maximumAlgebraicDepth, maximumCharts: charts,
                maximumFamilies: charts, maximumIdentityProofs: 0)
            let reference = try OriginalPhysicalAngleScalarDomain(originalRadians: alpha, using: &a)
            let parameterized = try OriginalPhysicalAngleScalarDomain(originalRadians: beta, using: &a)
            let phase = try OriginalPiScalarDomain(using: &a)
            let source = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedConeConeFullSnapshotProvider(
                reference: reference, parameterized: parameterized, phase: phase, tolerance: tolerance))
                .bind(curve, limits: sourceLimits, using: &a)
            let target = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedConeConeTargetSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            let span: ExactParameterInterval<OriginalPiValue>
            if let range = options.curveRange {
                span = try .checked(field: phase, lower: .finite(phase.binary64(exactly: range.lower, using: &a)),
                    upper: .finite(phase.binary64(exactly: range.upper, using: &a)), depth: .init(value: 0, coefficient: 0), using: &a)
            } else { span = try .checked(field: phase, lower: .negativeInfinity, upper: .positiveInfinity,
                depth: .init(value: 0, coefficient: 0), using: &a) }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<OriginalPiValue>].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalPiValue>.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ScalarInterval?.self))
            let relation = try OriginalCertifiedConeConePlaneRelation.resolve(source: source, target: target,
                curveIntervals: [[span]], planeRanges: [options.surfaceURange, options.surfaceVRange],
                maximumPoints: options.maximumCandidateCount, limits: limits, tolerance: tolerance, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: relation.phaseOrdinals.count, of: CurveSurfaceIntersection.self))
            var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(relation.phaseOrdinals.count)
            for ordinal in relation.phaseOrdinals {
                try a.consumeWork(1)
                let bound = try source.original.bounds(phaseOrdinal: ordinal, tolerance: tolerance, using: &a)
                let tBounds: OutwardScalarInterval
                if ordinal == 0 { tBounds = .exact(0) }
                else {
                    guard let t = CanonicalSphereAngularPhase.piBounds.divided(by: .exact(2 * Double.pi)) else { throw ExactScalarFailure.unresolved }
                    tBounds = t
                }
                let t = try representative(tBounds, request: options.curveRange)
                let u = try representative(bound.planeU, request: options.surfaceURange)
                let v = try representative(bound.planeV, request: options.surfaceVRange)
                let residual = ((bound.planeU.upper - bound.planeU.lower) +
                    (bound.planeV.upper - bound.planeV.lower) + (tBounds.upper - tBounds.lower)).nextUp
                guard residual.isFinite, residual <= tolerance.distance else { throw ExactScalarFailure.unresolved }
                points.append(try .init(point: .init(x: 0, y: -v, z: u), curveParameter: t,
                    surfaceU: u, surfaceV: v, kind: .transverse, residual: residual, iterations: 1))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: points, overlaps: [], originalCertifiedConeConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }
    private func representative(_ bounds: OutwardScalarInterval, request: ScalarInterval?) throws -> Double {
        var value = bounds.lower * 0.5 + bounds.upper * 0.5
        if let request { value = max(request.lower, min(request.upper, value)) }
        guard value.isFinite, bounds.lower <= value, value <= bounds.upper else { throw ExactScalarFailure.unresolved }
        return value
    }
}
