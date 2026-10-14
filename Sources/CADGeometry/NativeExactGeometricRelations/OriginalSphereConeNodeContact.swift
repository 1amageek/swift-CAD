import CADCore

/// Exact T/XYZ/planeUV and all original parent UV behind one authored contact ordinal.
public struct OriginalSphereConeNodeContact: Sendable {
    public let relation:OriginalSphereConeNodePlaneRelation
    public let ordinal:Int
    public let parameter:OriginalSphereConeNodeCurveSnapshot.Field.Value
    public let x:OriginalSphereConeNodeCurveSnapshot.Field.Value
    public let z:OriginalSphereConeNodeCurveSnapshot.Field.Value
    public let coneU:OriginalSphereConeNodeCurveSnapshot.Field.Value
    public let coneV:OriginalSphereConeNodeCurveSnapshot.Field.Value
    public let sphereU:OriginalSphereConeNodeCurveSnapshot.Field.Value
    public let sphereLatitudeSine:OriginalSphereConeNodeCurveSnapshot.Field.Value
    public let isApex:Bool
    public let proofDepth:ExactScalarDepth
    public var imageDimension:Int { 0 }
    public var parameterDimension:Int { 0 }
    public var fiberDimension:Int { 0 }
    public var parentFiberDimension:Int { isApex ? 1:0 }
    public var incidentSide:Int { ordinal==0 ? 1:ordinal==2 ? -1:0 }
    /// Sphere V is B/(2*pi)*asin(sphereLatitudeSine), canonical latitude branch.
    public var field:OriginalSphereConeNodeCurveSnapshot.Field { relation.source.original.field }
    public func planeV<A:ExactScalarAdmission & ~Copyable>(using a:inout A) throws -> OriginalSphereConeNodeCurveSnapshot.Field.Value {
        try a.checkpoint();try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        return try field.negated(z,using:&a)
    }
}
