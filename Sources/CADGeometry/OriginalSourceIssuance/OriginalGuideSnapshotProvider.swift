import CADCore

/// Reuses original directed traversal binding and exact rational station import.
public struct OriginalGuideSnapshotProvider<Child:OriginalSourceSnapshotting>:OriginalSourceSnapshotting where Child.Input == Curve3D {
    public let child:Child
    public let field:OriginalExactScalarDomain
    public let tolerance:ModelingTolerance
    public init(child:Child,field:OriginalExactScalarDomain,tolerance:ModelingTolerance) {
        self.child=child;self.field=field;self.tolerance=tolerance
    }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OriginalGuideTraversalChain3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalGuideSnapshot<Child.Source>> {
        do {
            try a.checkpoint();try a.consumeWork(1);try input.validate(tolerance:tolerance)
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            typealias Binding=OriginalSourceBinding<OriginalTraversalSpanSnapshot<Child.Source>>
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:input.traversals.count,of:Binding.self))
            var bindings:[Binding]=[];bindings.reserveCapacity(input.traversals.count)
            var current=field,depth=0
            for traversal in input.traversals {
                try a.consumeWork(1)
                let binding=try DefaultOriginalSourceBindingIssuer(provider:OriginalTraversalSpanSnapshotProvider(child:child,field:current))
                    .bind(traversal,limits:.init(remainingSourceDepth:limits.remainingSourceDepth-1),using:&a)
                current=binding.original.field;depth=max(depth,binding.sourceDepth);bindings.append(binding)
            }
            let sourceDepth=depth.addingReportingOverflow(1)
            guard !sourceDepth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:input.stations.count,of:OriginalExactScalar.self))
            var stations:[OriginalExactScalar]=[];stations.reserveCapacity(input.stations.count)
            for station in input.stations { try a.consumeWork(1);stations.append(try current.rational(exactly:station,using:&a)) }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalGuideSnapshot<Child.Source>.self))
            let result=OriginalGuideSnapshot(original:copy input,field:current,traversals:bindings,stations:stations)
            try a.checkpoint();return .init(original:result,sourceDepth:sourceDepth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
