import CADCore

/// Child family validation is injected; algebraic endpoints retain their existing roots.
public struct OriginalTraversalSpanSnapshotProvider<Child: OriginalSourceSnapshotting>: OriginalSourceSnapshotting
    where Child.Input == Curve3D {
    public let child: Child
    public let field: OriginalExactScalarDomain
    public init(child: Child, field: OriginalExactScalarDomain) { self.child = child; self.field = field }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalCurveRootSpan3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalTraversalSpanSnapshot<Child.Source>> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalCurveRootSpan3D.self))
            let endpoints = try OriginalTraversalEndpointBinding.prepare([copy input], field: field, using: &admission)
            return try snapshotPrepared(endpoints[0], limits: limits, using: &admission)
        } catch { throw .init(preserving: error) }
    }
    func snapshotPrepared<A: ExactScalarAdmission & ~Copyable>(_ endpoints: OriginalTraversalEndpointBinding,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalTraversalSpanSnapshot<Child.Source>> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1)
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let binding = try DefaultOriginalSourceBindingIssuer(provider: child).bind(endpoints.original.source,
                limits: .init(remainingSourceDepth: limits.remainingSourceDepth - 1), using: &admission)
            let depth = binding.sourceDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.checkpoint()
            return .init(original: .init(original: endpoints.original, child: binding,
                start: endpoints.start, end: endpoints.end, field: endpoints.field), sourceDepth: depth.partialValue)
        } catch { throw .init(preserving: error) }
    }
}
