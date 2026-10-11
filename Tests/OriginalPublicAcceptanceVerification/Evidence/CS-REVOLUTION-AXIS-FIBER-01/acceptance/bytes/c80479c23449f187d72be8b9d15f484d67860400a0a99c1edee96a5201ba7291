import CADCore

/// Reuses the existing directed endpoint/traversal producer under the same admission.
public struct OriginalRevolutionSnapshotProvider<Child:OriginalSourceSnapshotting>:OriginalSourceSnapshotting where Child.Input == Curve3D {
    public let child:Child
    public let field:OriginalExactScalarDomain
    public let tolerance:ModelingTolerance
    public init(child:Child,field:OriginalExactScalarDomain,tolerance:ModelingTolerance) {
        self.child=child;self.field=field;self.tolerance=tolerance
    }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalRevolutionSurface3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalRevolutionSnapshot<Child.Source>> {
        do {
            try a.checkpoint();try a.consumeWork(1);try input.validate(tolerance:tolerance)
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            guard case .closed(let lower,let upper)=input.uDomain else { throw OriginalSourceIssuanceFailure.invalidSource }
            let generator=try DefaultOriginalSourceBindingIssuer(provider:OriginalTraversalSpanSnapshotProvider(child:child,field:field))
                .bind(input.generator,limits:.init(remainingSourceDepth:limits.remainingSourceDepth-1),using:&a)
            let depth=generator.sourceDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalRevolutionSnapshot<Child.Source>.self))
            let result=OriginalRevolutionSnapshot(original:copy input,originalGenerator:generator,originalLowerU:lower,originalUpperU:upper)
            try a.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
