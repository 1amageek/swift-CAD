import CADCore

/// Exact XYZ and complete original UV inverse relations, without rounded angles.
public struct OriginalApexSphereConeSurfaceMember: Sendable {
    public typealias Field = OriginalApexSphereConeSurfaceSnapshot.Field
    public let relation: OriginalApexSphereConeSurfaceRelation
    public let section: OriginalApexSphereConeSurfaceSection?
    public let apexConeU: Field.Value?
    public let slant: Field.Value
    public let x: Field.Value
    public let y: Field.Value
    public let z: Field.Value
    public let coneLabelOffset: Field.Value
    public let sphereLabelOffset: Field.Value
    public let proofDepth: ExactScalarDepth
    public var field: Field { relation.source.original.field }
    public var sphereIsFirst: Bool { relation.source.original.sphereIsFirst }
    public let stratum: OriginalApexSphereConeSurfaceComponent.Stratum
    init(relation: OriginalApexSphereConeSurfaceRelation, section: OriginalApexSphereConeSurfaceSection?,
        slant: Field.Value, x: Field.Value, y: Field.Value, z: Field.Value, coneLabelOffset: Field.Value,
        sphereLabelOffset: Field.Value, apexConeU: Field.Value?, proofDepth: ExactScalarDepth,
        stratum: OriginalApexSphereConeSurfaceComponent.Stratum) {
        self.relation = relation; self.section = section; self.slant = slant
        self.x = x; self.y = y; self.z = z; self.coneLabelOffset = coneLabelOffset
        self.sphereLabelOffset = sphereLabelOffset; self.apexConeU = apexConeU
        self.proofDepth = proofDepth; self.stratum = stratum
    }
    static func apex<A: ExactScalarAdmission & ~Copyable>(relation: OriginalApexSphereConeSurfaceRelation,
        coneU: Field.Value, sphereOffset: Field.Value, using a: inout A) throws -> Self {
        try a.withProofScope() { a in
        let f = relation.source.original.field, zero = try f.integer(0, using: &a)
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: Self.self))
        let result = Self(relation: relation, section: nil, slant: zero, x: try f.integer(1, using: &a),
            y: zero, z: zero, coneLabelOffset: zero, sphereLabelOffset: sphereOffset,
            apexConeU: coneU, proofDepth: try a.depth, stratum: .apex)
        try a.checkpoint(); return result
        }
    }
    /// Cone U is B/(2*pi)*2*atan(halfAngle)+coneLabelOffset; V is slant.
    public var coneHalfAngle: Field.Value? { section?.halfAngle }
    /// Sphere U is B/(2*pi)*atan2(-X,Y)+sphereLabelOffset.
    /// The principal atan2 branch is (-pi,pi]; every integer B lift is retained.
    public func sphereAzimuthArguments<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> (sine: Field.Value, cosine: Field.Value) {
        try relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        return (try field.negated(x, using: &a), y)
    }
    /// Sphere V is B/(2*pi)*asin(Z), on the original canonical latitude branch.
    public func sphereLatitudeSine<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws -> Field.Value {
        try relation.admitProof(limits: limits, using: &a); try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        return z
    }
    public func firstUV<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> OriginalApexSphereConeSurfaceUV {
        try uv(isSphere: sphereIsFirst, limits: limits, using: &a)
    }
    public func secondUV<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> OriginalApexSphereConeSurfaceUV {
        try uv(isSphere: !sphereIsFirst, limits: limits, using: &a)
    }
    private func uv<A: ExactScalarAdmission & ~Copyable>(isSphere: Bool, limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> OriginalApexSphereConeSurfaceUV {
        try relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        let period = try field.importing(relation.source.original.labelPeriod, using: &a)
        let u: OriginalApexSphereConeSurfaceUV.Coordinate, v: OriginalApexSphereConeSurfaceUV.Coordinate
        if isSphere && stratum == .apex {
            u = .authoredScalar(try field.subtracting(sphereLabelOffset, field.dividing(period, field.integer(4, using: &a), using: &a), using: &a))
            v = .authoredScalar(try field.integer(0, using: &a))
        } else if isSphere {
            u = .sphereAzimuthLabel(sineArgument: try field.negated(x, using: &a), cosineArgument: y,
                period: period, offset: sphereLabelOffset)
            v = .sphereLatitudeLabel(sine: z, period: period)
        } else {
            if let apexConeU { u = .authoredScalar(apexConeU) }
            else {
                guard let section else { throw OriginalDomainIdentityFailure.invalidDomain }
                u = .coneAngularLabel(halfAngle: section.halfAngle, period: period, offset: coneLabelOffset)
            }
            v = .authoredScalar(slant)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalApexSphereConeSurfaceUV.self))
        let result = OriginalApexSphereConeSurfaceUV(member: self, isSphere: isSphere, u: u, v: v)
        try a.checkpoint(); return result
    }

}
