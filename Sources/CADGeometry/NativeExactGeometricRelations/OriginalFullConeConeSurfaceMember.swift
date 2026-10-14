import CADCore

/// Exact original XYZ and both signed slants with their independent coefficient owners.
public struct OriginalFullConeConeSurfaceMember: Sendable {
    public typealias Field = OriginalFullConeConeSurfaceSnapshot.Field
    public let section: OriginalFullConeConeSurfaceSection
    public let branch: Int
    public let parameterizedSlant: OriginalConeConeSurfaceCoordinate
    public let referenceSlant: OriginalConeConeSurfaceCoordinate
    public let x: OriginalConeConeSurfaceCoordinate
    public let y: OriginalConeConeSurfaceCoordinate
    public let z: OriginalConeConeSurfaceCoordinate
    public let parameterizedLabelOffset: Field.Value
    public let referenceLabelOffset: Field.Value
    public let proofDepth: ExactScalarDepth
    public var field: Field { section.field }
    public func firstUV<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalFullConeConeSurfaceUV {
        try uv(isReference: section.relation.source.original.referenceIsFirst, limits: limits, using: &a)
    }
    public func secondUV<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws -> OriginalFullConeConeSurfaceUV {
        try uv(isReference: !section.relation.source.original.referenceIsFirst, limits: limits, using: &a)
    }
    private func uv<A: ExactScalarAdmission & ~Copyable>(isReference: Bool, limits: OriginalDomainIdentityLimits,
        using a: inout A) throws -> OriginalFullConeConeSurfaceUV {
        try section.relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        let f = field, values = section.sourceValues
        let period = try f.importing(section.relation.source.original.labelPeriod, using: &a)
        let u: OriginalFullConeConeSurfaceUV.AngularCoordinate, v: OriginalConeConeSurfaceCoordinate
        if isReference {
            u = .principalAzimuth(sineArgument: try f.multiplying(values.parameterizedSine, values.sine, using: &a),
                cosineArgument: values.parameterizedCosine, period: period, offset: referenceLabelOffset)
            v = referenceSlant
        } else {
            u = .circleChart(halfAngle: section.halfAngle, period: period, offset: parameterizedLabelOffset)
            v = parameterizedSlant
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalFullConeConeSurfaceUV.self))
        let result = OriginalFullConeConeSurfaceUV(member: self, isReference: isReference, u: u, v: v)
        try a.checkpoint(); return result
    }
}
