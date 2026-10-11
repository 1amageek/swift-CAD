import CADCore

/// One immutable public owner, sharing the complete pair proof with every point.
public final class OriginalAngularPlaneGeometricRelations: OriginalAngularPlaneRelationReading {
    public typealias Original = OriginalAngularPlaneExactPoint.Original
    public let original: Original
    public let pairs: [ExactGeometricGraphRelation<OriginalPiScalarDomain>]
    public let exactPoints: [OriginalAngularPlaneExactPoint]
    public var isEmpty: Bool { pairs.isEmpty }
    public var hasPositiveDimensionalSolutions: Bool { pairs.contains { $0.hasPositiveDimensionalSolutions } }
    public var hasPositiveDimensionalImage: Bool { pairs.contains { $0.hasPositiveDimensionalImage } }
    private init(original:Original,pairs:[ExactGeometricGraphRelation<OriginalPiScalarDomain>],points:[OriginalAngularPlaneExactPoint]) {
        self.original=original;self.pairs=pairs;self.exactPoints=points
    }
    static func resolve<A: ExactScalarAdmission & ~Copyable>(_ original:Original,
        limits:OriginalDomainIdentityLimits,geometryLimits:ExactGeometricRelationLimits,
        maximumPoints:Int,using a:inout A) throws -> OriginalAngularPlaneGeometricRelations {
        try a.checkpoint();try original.admitProof(limits:limits,using:&a)
        guard original.pairs.count <= maximumPoints else { throw ExactGeometricRelationFailure.resultLimit }
        let resolver=DefaultExactGeometricGraphRelationResolver<OriginalPiScalarDomain>()
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:original.pairs.count,of:ExactGeometricGraphRelation<OriginalPiScalarDomain>.self))
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:original.pairs.count,of:OriginalAngularPlaneExactPoint.self))
        var pairs:[ExactGeometricGraphRelation<OriginalPiScalarDomain>]=[],points:[OriginalAngularPlaneExactPoint]=[]
        pairs.reserveCapacity(original.pairs.count);points.reserveCapacity(original.pairs.count)
        for pair in original.pairs {
            try a.consumeWork(1)
            let geometry=try resolver.resolve(pair.relation,limits:geometryLimits,using:&a)
            guard geometry.strata.count == 1,geometry.strata[0].parameterDimension == 0,
                geometry.strata[0].imageDimension == 0,geometry.strata[0].fiberDimension == 0 else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
            let point=try resolver.point(atParameterOrdinal:0,in:geometry,using:&a)
            guard point.parameters.count == 3 else { throw ExactGeometricRelationFailure.invalidCoverage }
            let root=original.zeros.roots[pair.rootOrdinal],decision=original.decisions[pair.rootOrdinal],field=point.witness.field
            guard try field.compare(point.parameters[0],field.importingBase(root.parameter,using:&a),using:&a) == .equal,
                try field.compare(point.parameters[1],field.importingBase(decision.uv[0],using:&a),using:&a) == .equal,
                try field.compare(point.parameters[2],field.importingBase(decision.uv[1],using:&a),using:&a) == .equal else {
                throw ExactGeometricRelationFailure.invalidCoverage
            }
            pairs.append(geometry);points.append(.init(original:original,rootOrdinal:pair.rootOrdinal,local:point))
        }
        let header=try exactScalarPayloadBytes(count:2,of:UInt.self)
        let payload=MemoryLayout<(Original,[ExactGeometricGraphRelation<OriginalPiScalarDomain>],[OriginalAngularPlaneExactPoint])>.stride
        let bytes=header.addingReportingOverflow(payload)
        guard !bytes.overflow else { throw ExactScalarFailure.countOverflow }
        try a.retainStorage(bytes:bytes.partialValue)
        let result=OriginalAngularPlaneGeometricRelations(original:original,pairs:pairs,points:points)
        try a.checkpoint();return result
    }
}
