import CADCore

/// Sealed root-selected normalized T law. The physical phase is pi*(branch+T).
public struct OriginalSphereConeNodeTraversal: Sendable {
    public let source: OriginalApexSphereConeSurfaceSnapshot
    public let branch: Int
    public let proofDepth: ExactScalarDepth
    init(source:OriginalApexSphereConeSurfaceSnapshot,branch:Int,proofDepth:ExactScalarDepth) {
        self.source=source;self.branch=branch;self.proofDepth=proofDepth
    }
    public func intrinsicLabel<A:ExactScalarAdmission & ~Copyable>(parameter:OriginalApexSphereConeSurfaceSnapshot.Field.Value,
        using a:inout A) throws -> OriginalApexSphereConeSurfaceSnapshot.Field.Value {
        try a.checkpoint();try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        let f=source.field,t=try f.importing(parameter,using:&a)
        guard try f.sign(of:t,using:&a) != .negative,
            try f.compare(t,f.integer(1,using:&a),using:&a) != .greater else { throw OriginalSourceIssuanceFailure.invalidSource }
        let phase=try f.adding(f.integer(branch,using:&a),t,using:&a)
        let label=try f.dividing(f.multiplying(source.labelPeriod,phase,using:&a),f.integer(2,using:&a),using:&a)
        try a.checkpoint();return label
    }
}
