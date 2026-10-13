import CADCore

/// Publishes the checked original full traversal and both parent UV families.
struct OriginalCertifiedCoaxialPublicProducer {
    private typealias Base = OriginalPhysicalAngleScalarDomain
    private typealias Admission = NativeExactPublicAdmission<NativeCurveSurfacePointAllowance>
    private typealias Interval = ExactParameterInterval<Base.Value>

    func resolve(curve: Curve3D, surface: Surface3D, options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance, invocation: CurveSurfaceQueryInvocation? = nil,
        retainingRelations: Bool = false) throws -> CurveSurfaceIntersectionResult? {
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
            let usage = try NativeCurveSurfacePointAllowance(options: options, invocation: invocation)
            var a = Admission(usage: usage, maximumDepth: usage.maximumAlgebraicDepth)
            try a.checkpoint(); try invocation?.consume(depth: 0)
            let sourceLimits = try OriginalSourceIssuanceLimits(
                remainingSourceDepth: invocation?.remainingSourceDepth ?? options.maximumSubdivisionDepth)
            let charts = min(invocation?.maximumSpanCount ?? options.maximumSubdivisionCells,
                options.maximumSubdivisionCells)
            let limits = try OriginalDomainIdentityLimits(source: sourceLimits,
                maximumTransportDepth: usage.maximumAlgebraicDepth, maximumCharts: charts,
                maximumFamilies: charts, maximumIdentityProofs: 0)
            let field = try Base(originalRadians: angle, using: &a)
            let source = try DefaultOriginalSourceBindingIssuer(
                provider: OriginalCertifiedCoaxialConeCylinderSnapshotProvider(field: field, tolerance: tolerance))
                .bind(curve, limits: sourceLimits, using: &a)
            let target = try DefaultOriginalSourceBindingIssuer(
                provider: OriginalCertifiedCoaxialTargetSnapshotProvider(tolerance: tolerance))
                .bind(surface, limits: sourceLimits, using: &a)
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: [Interval].self))
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 3, of: Interval.self))
            let curveIntervals = [[try interval(options.curveRange, field: field, using: &a)]]
            let targetIntervals = [[try interval(options.surfaceURange, field: field, using: &a)],
                [try interval(options.surfaceVRange, field: field, using: &a)]]
            let relation = try OriginalCertifiedCoaxialCurveSurfaceRelation.resolve(source: source,
                target: target, curveIntervals: curveIntervals, targetIntervals: targetIntervals,
                maximumPoints: options.maximumCandidateCount, limits: limits, using: &a)
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
            var points: [CurveSurfaceIntersection] = []
            if !relation.planeParameters.isEmpty {
                let bounds = try heightBounds(original, tolerance: tolerance, using: &a)
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
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: CurveSurfaceIntersectionResult.self))
            let result = CurveSurfaceIntersectionResult(points: points, overlaps: [], originalCertifiedCoaxialRelation: relation)
            try a.checkpoint(); return result
        } catch { throw NativeExactGeometryPublicationFailure.published(error, tolerance: tolerance) }
    }

    private func interval(_ range: ScalarInterval?, field: Base, using a: inout Admission) throws -> Interval {
        let depth = try ExactScalarDepth(value: 0, coefficient: 0)
        guard let range else {
            return try .checked(field: field, lower: .negativeInfinity, upper: .positiveInfinity,
                depth: depth, using: &a)
        }
        return try .checked(field: field, lower: .finite(field.binary64(exactly: range.lower, using: &a)),
            upper: .finite(field.binary64(exactly: range.upper, using: &a)), depth: depth, using: &a)
    }

    private func heightBounds(_ original: CertifiedConeCylinderIntersectionCurve,
        tolerance: ModelingTolerance, using a: inout Admission) throws -> OutwardScalarInterval {
        guard case .analytic(.cone(_, _, let angle)) = original.coneSurface else {
            throw OriginalSourceIssuanceFailure.invalidSource
        }
        // The synchronous evaluator borrows the same query allowance. No new
        // budget, regenerated metric or libm approximation supplies authority.
        var usage = a.usage
        defer { a.usage = usage }
        let trig = try CertifiedRotationTrigonometry.evaluate(.exact(angle), tolerance: tolerance,
            consumeWork: { try usage.consumeExactWork(1) })
        guard trig.sine.lower > 0, let height = trig.cosine.divided(by: trig.sine) else {
            throw ExactScalarFailure.unresolved
        }
        return original.componentKind == .negativeFullBranch ? height : -height
    }
}
