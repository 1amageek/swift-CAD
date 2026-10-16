import CADCore

/// Publishes original physical full branches without a rounded parent-UV reconstruction.
struct OriginalCertifiedSphereConePublicProducer {
    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution)
        throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        // FIXME(INCOMPLETE_IMPLEMENTATION): This route owns the two supported
        // full branches and the migrated fixed R2 bounded branch on planeY0/uX.
        // Other bounded, open, apex and other pairs need their whole original source/UV receipts
        // before their existing dispatch counts as complete original intersection.
        guard OriginalCertifiedSphereConeFullSnapshotProvider.supports(curve),
            OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(surface),
            case .certifiedIntersection(.sphereCone(let original)) = curve,
            case .analytic(.cone(_, _, let angle)) = original.coneSurface else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts = min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans), options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: a.effectiveLimits.maximumTransportDepth, maximumCharts: charts,
                maximumFamilies: min(charts, a.effectiveLimits.maximumFamilies), maximumIdentityProofs: 0)
            let physical = try OriginalPhysicalAngleScalarDomain(originalRadians: angle, using: &a)
            let phase = try OriginalPiScalarDomain(using: &a)
            let provider = OriginalCertifiedSphereConeFullSnapshotProvider(physical: physical, phaseField: phase,
                maximumExtensionLevel: a.effectiveLimits.maximumValueDepth, tolerance: tolerance)
            let source = try DefaultOriginalSourceBindingIssuer(provider: provider).bind(curve, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(first: .init(source: source))
            let target = try DefaultOriginalSourceBindingIssuer(provider: OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(target.sourceDepth)
            a.context = a.context.retaining(second: .init(source: target))
            a.context = a.context.at(stage: .domain)
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
            a.context = a.context.at(stage: .relation)
            let relation = try OriginalCertifiedSphereConePlaneRelation.resolve(source: source, target: target,
                curveIntervals: [[interval]], planeRanges: [options.surfaceURange, options.surfaceVRange],
                maximumPoints: min(options.maximumCandidateCount, a.effectiveLimits.maximumResults), limits: limits, using: &a)
            a.context = a.context.at(stage: .refinement)
            let bounds = try pointBounds(original, tolerance: tolerance, using: &a)
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: relation.phaseOrdinals.count, of: CurveSurfaceIntersection.self))
            var points: [CurveSurfaceIntersection] = []; points.reserveCapacity(relation.phaseOrdinals.count)
            for ordinal in relation.phaseOrdinals {
                try a.consumeWork(1)
                let coordinate = bounds[ordinal]
                let tInterval: OutwardScalarInterval
                if original.componentKind == .boundedAngularInterval {
                    tInterval = .exact(ordinal == 0 ? 0.25 : 0.75)
                } else {
                    let tBounds = CanonicalSphereAngularPhase.piBounds * .exact(ordinal == 0 ? 1 : 3)
                    guard let interval = tBounds.divided(by: .exact(4 * Double.pi)) else { throw ExactScalarFailure.unresolved }
                    tInterval = interval
                }
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
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: points, overlaps: [], originalCertifiedSphereConeRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }
    private func pointBounds(_ original: CertifiedSphereConeIntersectionCurve, tolerance: ModelingTolerance,
        using a: inout OriginalQueryExecution) throws -> [(x: OutwardScalarInterval, z: OutwardScalarInterval)] {
        guard case .analytic(.cone(_, _, let angle)) = original.coneSurface else { throw OriginalSourceIssuanceFailure.invalidSource }

        let trig = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance,
            using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: (OutwardScalarInterval, OutwardScalarInterval).self))
        var result: [(x: OutwardScalarInterval, z: OutwardScalarInterval)] = []; result.reserveCapacity(2)
        let bounded = original.componentKind == .boundedAngularInterval
        for ordinal in 0..<2 {
            let sign = bounded || ordinal == 0 ? 1.0 : -1.0
            try a.consumeWork(1)
            let b = .exact(sign * (bounded ? 2 : 1)) * trig.sine + .exact(4) * trig.cosine
            let d = b * b - .exact(bounded ? 16 : 8)
            guard d.lower > 0, d.isFinite else { throw ExactScalarFailure.unresolved }
            let root = OutwardScalarInterval(lower: d.lower.squareRoot().nextDown, upper: d.upper.squareRoot().nextUp)
            let negative = original.componentKind == .negativeFullBranch || (bounded && ordinal == 1)
            let slant = negative ? b - root : b + root
            let x = .exact(bounded ? 2 : 1) - .exact(sign) * trig.sine * slant
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
