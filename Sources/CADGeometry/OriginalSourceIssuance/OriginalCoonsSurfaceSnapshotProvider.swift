import CADCore

/// Uses one exact endpoint field and separately injected actual boundary families.
public struct OriginalCoonsSurfaceSnapshotProvider<Bottom: OriginalSourceSnapshotting,
    Top: OriginalSourceSnapshotting, Left: OriginalSourceSnapshotting, Right: OriginalSourceSnapshotting>: OriginalSourceSnapshotting
    where Bottom.Input == Curve3D, Top.Input == Curve3D, Left.Input == Curve3D, Right.Input == Curve3D {
    public let bottom: Bottom
    public let top: Top
    public let left: Left
    public let right: Right
    public let field: OriginalExactScalarDomain
    public let tolerance: ModelingTolerance
    public init(bottom: Bottom, top: Top, left: Left, right: Right,
        field: OriginalExactScalarDomain, tolerance: ModelingTolerance) {
        self.bottom = bottom; self.top = top; self.left = left; self.right = right
        self.field = field; self.tolerance = tolerance
    }
    private struct PreparedBoundary<Child: OriginalSourceSnapshotting>: OriginalSourceSnapshotting where Child.Input == Curve3D {
        let provider: OriginalTraversalSpanSnapshotProvider<Child>
        func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalTraversalEndpointBinding,
            limits: OriginalSourceIssuanceLimits, using admission: inout A
        ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalTraversalSpanSnapshot<Child.Source>> {
            try provider.snapshotPrepared(copy input, limits: limits, using: &admission)
        }
    }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing OriginalCoonsSurface3D,
        limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalCoonsSurfaceSnapshot<Bottom.Source, Top.Source, Left.Source, Right.Source>> {
        do {
            try admission.checkpoint(); try admission.consumeWork(1); try input.validate(tolerance: tolerance)
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            // FIXME(INCOMPLETE_IMPLEMENTATION): Discontinuous boundaries require the
            // source/domain issuer's directed one-sided endpoint contract. This actual
            // provider currently preserves the existing continuous Coons preparation
            // scope; whole-family completion cannot count this rejection as support.
            guard input.hasOriginalPositionContinuity else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            try admission.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: OriginalCurveRootSpan3D.self))
            let raw = [input.vMinimumBoundary, input.vMaximumBoundary, input.uMinimumBoundary, input.uMaximumBoundary]
            let endpoints = try OriginalTraversalEndpointBinding.prepare(raw, field: field, using: &admission)
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            let b = try DefaultOriginalSourceBindingIssuer(provider: PreparedBoundary(provider:
                OriginalTraversalSpanSnapshotProvider(child: bottom, field: endpoints[0].field))).bind(endpoints[0], limits: children, using: &admission)
            let t = try DefaultOriginalSourceBindingIssuer(provider: PreparedBoundary(provider:
                OriginalTraversalSpanSnapshotProvider(child: top, field: endpoints[0].field))).bind(endpoints[1], limits: children, using: &admission)
            let l = try DefaultOriginalSourceBindingIssuer(provider: PreparedBoundary(provider:
                OriginalTraversalSpanSnapshotProvider(child: left, field: endpoints[0].field))).bind(endpoints[2], limits: children, using: &admission)
            let r = try DefaultOriginalSourceBindingIssuer(provider: PreparedBoundary(provider:
                OriginalTraversalSpanSnapshotProvider(child: right, field: endpoints[0].field))).bind(endpoints[3], limits: children, using: &admission)
            let depth = max(max(b.sourceDepth, t.sourceDepth), max(l.sourceDepth, r.sourceDepth)).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try admission.checkpoint()
            return .init(original: .init(original: copy input, bottom: b, top: t, left: l, right: r,
                field: endpoints[0].field), sourceDepth: depth.partialValue)
        } catch { throw .init(preserving: error) }
    }
}
