import CADCore

/// Publishes the complete local traversal by consuming the same child receipt.
struct OriginalCertifiedPairLiftPublicProducer {
    private typealias Field = OriginalPhysicalAngleScalarDomain
    private typealias Admission = NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    private typealias Interval = ExactParameterInterval<Field.Value>
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil) throws -> CurveSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): These ordinary/callback lift entries
        // own the supported coaxial pair's two roles and closed fraction windows
        // against planeY0/uX. Other pairs/windows/targets need complete original
        // parameter/source receipts before their legacy paths count as acceptance.
        guard OriginalCertifiedPairLiftSnapshotProvider.supports(curve),
            OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(surface),
            case .surfaceLift(let lift) = curve, case .certifiedAnalyticPair(let pcurve) = lift.parameterCurve,
            case .coneCylinder(let original) = pcurve.intersection.definition,
            case .analytic(.cone(_, _, let angle)) = original.coneSurface else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
            var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
            try a.checkpoint(); try invocation?.consume(depth: 0)
            let sourceLimits = try OriginalSourceIssuanceLimits(remainingSourceDepth:
                invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts = min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells, options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: usage.maximumAlgebraicDepth, maximumCharts: charts, maximumFamilies: charts, maximumIdentityProofs: 0)
            let field = try Field(originalRadians: angle, using: &a)
            let source = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedPairLiftSnapshotProvider(field: field, tolerance: tolerance))
                .bind(curve, limits: sourceLimits, using: &a)
            let target = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: [Interval].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
            let relation = try OriginalCertifiedPairLiftPlaneRelation.resolve(source: source, target: target,
                targetIntervals: [[try interval(options.surfaceURange, field: field, using: &a)],
                    [try interval(options.surfaceVRange, field: field, using: &a)]],
                requested: [[try interval(options.curveRange, field: field, using: &a)]],
                maximumPoints: options.maximumCandidateCount, limits: limits, using: &a)
            var points: [CurveSurfaceIntersection] = []
            if !relation.contacts.isEmpty {
                let bounds = try source.original.child.original.heightBounds(tolerance: tolerance, using: &a)
                let width = (bounds.upper - bounds.lower).nextUp
                guard bounds.isFinite, width.isFinite, width * 2 <= tolerance.distance else { throw ExactScalarFailure.unresolved }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: relation.contacts.count, of: CurveSurfaceIntersection.self))
                points.reserveCapacity(relation.contacts.count)
                for contact in relation.contacts {
                    try a.consumeWork(1)
                    let rBounds: OutwardScalarInterval
                    if try field.compare(contact.parameter, field.integer(0, using: &a), using: &a) == .equal { rBounds = .exact(0) }
                    else if try field.compare(contact.parameter, field.integer(1, using: &a), using: &a) == .equal { rBounds = .exact(1) }
                    else {
                        let child = OutwardScalarInterval.exact(contact.childOrdinal == 0 ? 0.25 : 0.75)
                        guard let result = (child - .exact(pcurve.startFraction)).divided(by:
                            .exact(pcurve.endFraction) - .exact(pcurve.startFraction)) else { throw ExactScalarFailure.unresolved }
                        rBounds = result
                    }
                    let r = try representative(rBounds, request: options.curveRange)
                    let v = try representative(-bounds, request: options.surfaceVRange)
                    let residual = (width * 2 + rBounds.upper - rBounds.lower).nextUp
                    guard residual.isFinite, residual <= tolerance.distance else { throw ExactScalarFailure.unresolved }
                    let x = contact.childOrdinal == 0 ? -1.0 : 1.0
                    points.append(try .init(point: .init(x: x, y: 0, z: -v), curveParameter: r,
                        surfaceU: x, surfaceV: v, kind: .transverse, residual: residual, iterations: 1))
                }
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: points, overlaps: [], originalCertifiedPairLiftRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }
    private func interval(_ range: ScalarInterval?, field: Field, using a: inout Admission) throws -> Interval {
        if let range { return try .checked(field: field, lower: .finite(field.binary64(exactly: range.lower, using: &a)),
            upper: .finite(field.binary64(exactly: range.upper, using: &a)), depth: .init(value: 0, coefficient: 0), using: &a) }
        return try .checked(field: field, lower: .negativeInfinity, upper: .positiveInfinity, depth: .init(value: 0, coefficient: 0), using: &a)
    }
    private func representative(_ bounds: OutwardScalarInterval, request: ScalarInterval?) throws -> Double {
        var value = bounds.lower * 0.5 + bounds.upper * 0.5
        if let request { value = max(request.lower, min(request.upper, value)) }
        guard value.isFinite, bounds.lower <= value, value <= bounds.upper else { throw ExactScalarFailure.unresolved }
        return value
    }
}
