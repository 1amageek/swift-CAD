import CADCore

public struct OriginalGraphRollingBallSnapshotProvider: OriginalSourceSnapshotting {
    public let field: OriginalExactScalarDomain
    public init(field: OriginalExactScalarDomain) { self.field=field }
    public func snapshot<A: ExactScalarAdmission & ~Copyable>(_ input: borrowing RollingBallBlendSurface3D,
        limits: OriginalSourceIssuanceLimits,using a: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalGraphRollingBallSnapshot> {
        do {
            try a.checkpoint();try a.consumeWork(1);try input.validateConstructionParameters()
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
            let issuer=DefaultOriginalSourceBindingIssuer(provider:OriginalRollingBallCurveSnapshotProvider(field:field,tolerance:input.tolerance))
            let center=try issuer.bind(input.centerSpine,limits:children,using:&a)
            let first=try issuer.bind(input.firstContact,limits:children,using:&a)
            let second=try issuer.bind(input.secondContact,limits:children,using:&a)
            let total=max(center.sourceDepth,max(first.sourceDepth,second.sourceDepth)).addingReportingOverflow(1)
            guard !total.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalGraphRollingBallSnapshot.self))
            let result=OriginalGraphRollingBallSnapshot(original:copy input,center:center,first:first,second:second)
            try a.checkpoint();return .init(original:result,sourceDepth:total.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
