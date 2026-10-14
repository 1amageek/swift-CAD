import CADCore

/// Source-retaining XYZ definition offset+cosineCoefficient*cos(U)+sineCoefficient*sin(U).
public struct OriginalCoincidentConePosition: Sendable {
    public struct Coordinate: Sendable {
        public let offset: OriginalPhysicalAngleValue
        public let cosineCoefficient: OriginalPhysicalAngleValue
        public let sineCoefficient: OriginalPhysicalAngleValue
    }
    public let source: OriginalCoincidentConeSnapshot
    public let intrinsicLabel: OriginalPhysicalAngleValue
    public let slant: OriginalPhysicalAngleValue
    public let radial: OriginalPhysicalAngleValue
    public let axial: OriginalPhysicalAngleValue
    public let proofDepth: ExactScalarDepth
    public var cosine: OriginalSourceCoordinateFunction<OriginalPhysicalAngleValue> { .intrinsicCosine(axis:0) }
    public var sine: OriginalSourceCoordinateFunction<OriginalPhysicalAngleValue> { .intrinsicSine(axis:0) }
    public func coordinate<A: ExactScalarAdmission & ~Copyable>(row:Int,using a:inout A) throws -> Coordinate {
        try a.checkpoint();try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
        guard row>=0,row<3 else { throw OriginalSourceIssuanceFailure.invalidSource }
        let original=source.firstLaw.source.original,f=source.field
        let origin=try f.binary64(exactly:original.center(in:row),using:&a)
        let u=try f.binary64(exactly:original.frame(row:row,column:0),using:&a)
        let v=try f.binary64(exactly:original.frame(row:row,column:1),using:&a)
        let axis=try f.binary64(exactly:original.frame(row:row,column:2),using:&a)
        let offset=try f.adding(origin,f.multiplying(axis,axial,using:&a),using:&a)
        let c=try f.multiplying(u,radial,using:&a),s=try f.multiplying(v,radial,using:&a)
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:Coordinate.self))
        let result=Coordinate(offset:offset,cosineCoefficient:c,sineCoefficient:s)
        try a.checkpoint();return result
    }
}
