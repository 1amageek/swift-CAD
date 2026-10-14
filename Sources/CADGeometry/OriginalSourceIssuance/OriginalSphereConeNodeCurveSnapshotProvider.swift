import CADCore

public struct OriginalSphereConeNodeCurveSnapshotProvider: OriginalSourceSnapshotting {
    public init() {}
    public static func traversal(_ curve:Curve3D) -> OriginalSphereConeNodeTraversal? {
        guard case .certifiedIntersection(.sphereCone(let value))=curve else { return nil }
        return value.originalNodeTraversal
    }
    public func snapshot<A:ExactScalarAdmission & ~Copyable>(_ input:borrowing Curve3D,
        limits:OriginalSourceIssuanceLimits,using a:inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalSourceSnapshot<OriginalSphereConeNodeCurveSnapshot> {
        let input=copy input
        do {
            try a.checkpoint();try a.consumeWork(1)
            guard limits.remainingSourceDepth>=2 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            guard let node=Self.traversal(input) else { throw OriginalSourceIssuanceFailure.unsupportedRepresentation }
            try a.admitDepth(value:node.proofDepth.value,coefficient:node.proofDepth.coefficient)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalSphereConeNodeCurveSnapshot.self))
            let result=OriginalSphereConeNodeCurveSnapshot(original:input,traversal:node,proofDepth:node.proofDepth)
            try a.checkpoint();return .init(original:result,sourceDepth:2)
        } catch { throw .init(preserving:error) }
    }
}
