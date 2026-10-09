import CADCore

public struct OriginalOffsetSnapshotProvider<Child:OriginalSourceSnapshotting>:OriginalSourceSnapshotting where Child.Input == Surface3D {
    public let child:Child
    public init(child:Child) { self.child=child }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing OffsetSurface3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalOffsetSnapshot<Child.Source>> {
        do {
            try a.checkpoint();try a.consumeWork(1)
            guard input.distance.isFinite else { throw GeometryError.invalidDistance(input.distance) }
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            let binding=try DefaultOriginalSourceBindingIssuer(provider:child).bind(input.source,
                limits:.init(remainingSourceDepth:limits.remainingSourceDepth-1),using:&a)
            let depth=binding.sourceDepth.addingReportingOverflow(1)
            guard !depth.overflow else { throw OriginalSourceIssuanceFailure.countOverflow }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalOffsetSnapshot<Child.Source>.self))
            let result=OriginalOffsetSnapshot(original:copy input,originalChild:binding)
            try a.checkpoint();return .init(original:result,sourceDepth:depth.partialValue)
        } catch { throw .init(preserving:error) }
    }
}
