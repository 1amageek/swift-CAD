import CADCore

public struct OriginalRollingBallSnapshotProvider<Child: OriginalSourceSnapshotting>: OriginalSourceSnapshotting
    where Child.Input == Curve3D, Child.Source: OriginalBSplineSourceReading {
    public let child: Child
    public init(child: Child) { self.child = child }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing RollingBallBlendSurface3D,
        limits: OriginalSourceIssuanceLimits, using a: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalRollingBallSnapshot<Child.Source>> {
        do {
            try a.checkpoint(); try a.consumeWork(1); try input.validateConstructionParameters()
            guard limits.remainingSourceDepth > 0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let issuer = DefaultOriginalSourceBindingIssuer(provider: child)
            let children = try OriginalSourceIssuanceLimits(remainingSourceDepth: limits.remainingSourceDepth - 1)
            // FIXME(INCOMPLETE_IMPLEMENTATION): General rolling-ball rails include lifts and
            // non-Native curves. This Native provider fails until their complete original
            // chart/parameter capabilities exist; it does not complete the whole family.
            let center = try issuer.bind(input.centerSpine, limits: children, using: &a)
            let first = try issuer.bind(input.firstContact, limits: children, using: &a)
            let second = try issuer.bind(input.secondContact, limits: children, using: &a)
            let depth = max(center.sourceDepth, max(first.sourceDepth, second.sourceDepth)).addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalRollingBallSnapshot<Child.Source>.self))
            let result = OriginalRollingBallSnapshot(original: copy input, center: center, first: first, second: second)
            try a.checkpoint(); return .init(original: result, sourceDepth: depth.partialValue)
        } catch { throw .init(preserving: error) }
    }
}
