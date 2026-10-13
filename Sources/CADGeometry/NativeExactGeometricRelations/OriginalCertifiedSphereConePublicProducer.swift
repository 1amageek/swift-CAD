import CADCore

/// Publishes original physical full branches without a rounded parent-UV reconstruction.
struct OriginalCertifiedSphereConePublicProducer {
    private typealias Admission = NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil)
        throws -> CurveSurfaceIntersectionResult? {
        // FIXME(INCOMPLETE_IMPLEMENTATION): This route owns the two supported
        // full sphere-cone branches and the declared planeY0/uX target. Bounded,
        // open, apex and other pairs need their whole original source/UV receipts
        // before their existing dispatch counts as complete original intersection.
        guard OriginalCertifiedSphereConeFullSnapshotProvider.supports(curve),
            OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(surface),
            case .certifiedIntersection(.sphereCone(let original)) = curve,
            case .analytic(.cone(_, _, let angle)) = original.coneSurface else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            let usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
            var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
            try a.checkpoint(); try invocation?.consume(depth: 0)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth: invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts = min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells, options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: usage.maximumAlgebraicDepth, maximumCharts: charts,
                maximumFamilies: charts, maximumIdentityProofs: 0)
            let physical = try OriginalPhysicalAngleScalarDomain(originalRadians: angle, using: &a)
            let phase = try OriginalPiScalarDomain(using: &a)
            let provider = OriginalCertifiedSphereConeFullSnapshotProvider(physical: physical, phaseField: phase,
                maximumExtensionLevel: usage.maximumAlgebraicDepth, tolerance: tolerance)
            let source = try DefaultOriginalSourceBindingIssuer(provider: provider).bind(curve, limits: sourceLimits, using: &a)
            let target = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            let interval: ExactParameterInterval<OriginalPiValue>
            if let range = options.curveRange {
                interval = try .checked(field: phase, lower: .finite(phase.binary64(exactly: range.lower, using: &a)),
                    upper: .finite(phase.binary64(exactly: range.upper, using: &a)), depth: .init(value: 0, coefficient: 0), using: &a)
            } else {
                interval = try .checked(field: phase, lower: .negativeInfinity, upper: .positiveInfinity,
                    depth: .init(value: 0, coefficient: 0), using: &a)
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: [ExactParameterInterval<OriginalPiValue>].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: ExactParameterInterval<OriginalPiValue>.self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: ScalarInterval?.self))
            let relation = try OriginalCertifiedSphereConePlaneRelation.resolve(source: source, target: target,
                curveIntervals: [[interval]], planeRanges: [options.surfaceURange, options.surfaceVRange],
                maximumPoints: options.maximumCandidateCount, limits: limits, using: &a)
            let bounds = try pointBounds(original, tolerance: tolerance, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: relation.phaseOrdinals.count, of: CurveSurfaceIntersection.self))
            var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(relation.phaseOrdinals.count)
            for ordinal in relation.phaseOrdinals {
                try a.consumeWork(1)
                let coordinate = bounds[ordinal]
                let tBounds = CanonicalSphereAngularPhase.piBounds * .exact(ordinal == 0 ? 1 : 3)
                guard let tInterval = tBounds.divided(by: .exact(4 * Double.pi)) else { throw ExactScalarFailure.unresolved }
                let x = try representative(coordinate.x, request: options.surfaceURange)
                let v = try representative(-coordinate.z, request: options.surfaceVRange)
                let t = try representative(tInterval, request: options.curveRange)
                let residual = ((coordinate.x.upper - coordinate.x.lower) +
                    2 * (coordinate.z.upper - coordinate.z.lower) + (tInterval.upper - tInterval.lower)).nextUp
                guard residual.isFinite, residual <= tolerance.distance else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Original sphere-cone localization exceeds the requested output accuracy.")
                }
                points.append(try .init(point: .init(x: x, y: 0, z: -v), curveParameter: t,
                    surfaceU: x, surfaceV: v, kind: .transverse, residual: residual, iterations: 1))
            }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: points, overlaps: [], originalCertifiedSphereConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }
    private func pointBounds(_ original: CertifiedSphereConeIntersectionCurve, tolerance: ModelingTolerance,
        using a: inout Admission) throws -> [(x: OutwardScalarInterval, z: OutwardScalarInterval)] {
        guard case .analytic(.cone(_, _, let angle)) = original.coneSurface else { throw OriginalSourceIssuanceFailure.invalidSource }
        var usage = a.usage
        defer { a.usage = usage }
        let trig = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) })
        try usage.retainBytes(exactScalarPayloadBytes(count: 2, of: (OutwardScalarInterval, OutwardScalarInterval).self))
        var result: [(x: OutwardScalarInterval, z: OutwardScalarInterval)] = []; result.reserveCapacity(2)
        for sign in [1.0, -1.0] {
            try usage.consumeExactWork(1)
            let b = .exact(sign) * trig.sine + .exact(4) * trig.cosine
            let d = b * b - .exact(8)
            guard d.lower > 0, d.isFinite else { throw ExactScalarFailure.unresolved }
            let root = OutwardScalarInterval(lower: d.lower.squareRoot().nextDown, upper: d.upper.squareRoot().nextUp)
            let slant = original.componentKind == .negativeFullBranch ? b - root : b + root
            let x = .exact(1) - .exact(sign) * trig.sine * slant
            let z = .exact(-4) + trig.cosine * slant
            result.append((x, z))
        }
        return result
    }
    private func representative(_ bounds: OutwardScalarInterval, request: ScalarInterval?) throws -> Double {
        var value = bounds.lower * 0.5 + bounds.upper * 0.5
        if let request { value = max(request.lower, min(request.upper, value)) }
        guard value.isFinite, value >= bounds.lower, value <= bounds.upper else { throw ExactScalarFailure.unresolved }
        return value
    }
}
