import CADCore

/// Publishes the checked original full traversal and both parent UV families.
struct OriginalCertifiedCoaxialPublicProducer {
    private typealias Base = OriginalPhysicalAngleScalarDomain
    private typealias Interval = ExactParameterInterval<Base.Value>

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, using a: inout OriginalQueryExecution,
        retainingRelations: Bool = false) throws -> CurveSurfaceIntersectionResult? {
        a.context = a.context.at(stage: .request)
        try a.checkpoint()
        // FIXME(INCOMPLETE_IMPLEMENTATION): This ordinary route selects the two
        // unit coaxial full branches and their declared plane/cylinder targets.
        // Other certified variants require their own complete source and domain
        // receipts before their existing dispatch can count as exact completion.
        guard OriginalCertifiedCoaxialConeCylinderSnapshotProvider.supports(curve),
            case .certifiedIntersection(.coneCylinder(let original)) = curve,
            case .analytic(.cone(_, _, let angle)) = original.coneSurface,
            OriginalCertifiedCoaxialTargetSnapshotProvider.isPlane(surface)
                || surface == original.cylinderSurface else { return nil }
        do {
            try options.validate(tolerance: tolerance)
            try a.checkpoint()
            a.context = a.context.at(stage: .source)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth: a.effectiveLimits.remainingSourceDepth)
            let charts = min(min(a.effectiveLimits.maximumCharts, a.effectiveLimits.maximumSpans),
                options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: a.effectiveLimits.maximumTransportDepth, maximumCharts: charts,
                maximumFamilies: min(charts, a.effectiveLimits.maximumFamilies), maximumIdentityProofs: 0)
            let field = try Base(originalRadians: angle, using: &a)
            let source = try DefaultOriginalSourceBindingIssuer(
                provider: OriginalCertifiedCoaxialConeCylinderSnapshotProvider(field: field, tolerance: tolerance))
                .bind(curve, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(source.sourceDepth)
            a.context = a.context.retaining(first: .init(source: source))
            let target = try DefaultOriginalSourceBindingIssuer(
                provider: OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            try a.admitSourceDepth(target.sourceDepth)
            a.context = a.context.retaining(second: .init(source: target))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: [Interval].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
            a.context = a.context.at(stage: .domain)
            let curveIntervals = [[try interval(options.curveRange, field: field, using: &a)]]
            let targetIntervals = [[try interval(options.surfaceURange, field: field, using: &a)],
                [try interval(options.surfaceVRange, field: field, using: &a)]]
            a.context = a.context.at(stage: .relation)
            let relation = try OriginalCertifiedCoaxialCurveSurfaceRelation.resolve(source: source,
                target: target, curveIntervals: curveIntervals, targetIntervals: targetIntervals,
                maximumPoints: min(options.maximumCandidateCount, a.effectiveLimits.maximumResults), limits: limits, using: &a)
            if !retainingRelations && relation.hasPositiveDimensionalSolutions {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                    message: "Original certified curve contacts require the complete interval relation.")
            }
            // A restricted cylinder family may contain only isolated tuples. Its
            // symbolic lift indices still require the richer relation API.
            if !retainingRelations && relation.isCylinder && !relation.isEmpty {
                throw KernelError(phase: .geometry, code: .nonDiscreteIntersection, tolerance: tolerance,
                    message: "Original certified cylinder tuples require their retained lift relation.")
            }
            a.context = a.context.at(stage: .publication)
            var points: [CurveSurfaceIntersection] = []
            if !relation.planeParameters.isEmpty {
                a.context = a.context.at(stage: .refinement)
                let bounds = try source.original.heightBounds(tolerance: tolerance, using: &a)
                guard bounds.isFinite else { throw ExactScalarFailure.unresolved }
                let width = (bounds.upper - bounds.lower).nextUp
                guard width.isFinite, width * 2 <= tolerance.distance else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                        message: "Original certified height localization exceeds the requested accuracy.")
                }
                try a.retainStorage(bytes: exactScalarPayloadBytes(count: relation.planeParameters.count,
                    of: CurveSurfaceIntersection.self))
                points.reserveCapacity(relation.planeParameters.count)
                for parameter in relation.planeParameters {
                    try a.consumeWork(1)
                    let first = try field.compare(parameter, source.original.planeRoot(at: 0, using: &a), using: &a) == .equal
                    let t = first ? 0.25 : 0.75, x = first ? -1.0 : 1.0
                    let z = bounds.lower * 0.5 + bounds.upper * 0.5
                    var v = -z
                    if let range = options.surfaceVRange { v = max(range.lower, min(range.upper, v)) }
                    guard v >= -bounds.upper, v <= -bounds.lower else { throw ExactScalarFailure.unresolved }
                    points.append(try .init(point: .init(x: x, y: 0, z: z), curveParameter: t,
                        surfaceU: x, surfaceV: v, kind: .transverse, residual: width * 2, iterations: 1))
                }
            }
            a.context = a.context.at(stage: .publication)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: points, overlaps: [], originalCertifiedCoaxialRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance, context: a.context) }
    }

    private func interval(_ range: ScalarInterval?, field: Base, using a: inout OriginalQueryExecution) throws -> Interval {
        let depth = try ExactScalarDepth(value: 0, coefficient: 0)
        guard let range else {
            return try .checked(field: field, lower: .negativeInfinity, upper: .positiveInfinity,
                depth: depth, using: &a)
        }
        return try .checked(field: field, lower: .finite(field.binary64(exactly: range.lower, using: &a)),
            upper: .finite(field.binary64(exactly: range.upper, using: &a)), depth: depth, using: &a)
    }

}
