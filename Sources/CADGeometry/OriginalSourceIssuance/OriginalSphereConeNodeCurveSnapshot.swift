import CADCore

/// Retained generated T law and its three complete plane-Y contacts.
public struct OriginalSphereConeNodeCurveSnapshot: Sendable {
    public typealias Field=OriginalApexSphereConeSurfaceSnapshot.Field
    public let original: Curve3D
    public let traversal: OriginalSphereConeNodeTraversal
    public let proofDepth: ExactScalarDepth
    public var field: Field { traversal.source.field }
    public func critical<A:ExactScalarAdmission & ~Copyable>(ordinal:Int,using a:inout A)
        throws -> (parameter:Field.Value,x:Field.Value,z:Field.Value,slant:Field.Value,coneLabel:Field.Value,isApex:Bool) {
        try a.checkpoint();try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        guard ordinal>=0,ordinal<=2 else { throw OriginalSourceIssuanceFailure.invalidSource }
        let f=field,t=try f.dividing(f.integer(ordinal,using:&a),f.integer(2,using:&a),using:&a)
        let label=try traversal.intrinsicLabel(parameter:t,using:&a)
        let chart=traversal.branch
        let h=try f.integer(ordinal==1 ? 1:0,using:&a)
        let values=try traversal.source.sectionValues(chart:chart,halfAngle:h,using:&a)
        try a.checkpoint();return (t,values.x,values.z,values.slant,label,ordinal != 1)
    }
}
