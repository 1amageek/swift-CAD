import CADCore

/// Exact XYZ and complete original UV inverse relations, without rounded angles.
public struct OriginalBoundedSphereConeSurfaceMember: Sendable {
    public typealias Field = OriginalBoundedSphereConeSurfaceSnapshot.Field
    public let section: OriginalBoundedSphereConeSurfaceSection
    public let branch: Int
    public let slant: Field.Value
    public let x: Field.Value
    public let y: Field.Value
    public let z: Field.Value
    public let coneLabelOffset: Field.Value
    public let sphereLabelOffset: Field.Value
    public let proofDepth: ExactScalarDepth
    public var field: Field { section.field }
    public var sphereIsFirst: Bool { section.relation.source.original.sphereIsFirst }
    /// Cone U is B/(2*pi)*2*atan(halfAngle)+coneLabelOffset; V is slant.
    public var coneHalfAngle: Field.Value { section.halfAngle }
    /// Sphere U is B/(2*pi)*atan2(-X,Y)+sphereLabelOffset.
    /// The principal atan2 branch is (-pi,pi]; every integer B lift is retained.
    public func sphereAzimuthArguments<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> (sine: Field.Value, cosine: Field.Value) {
        try section.relation.admitProof(limits: limits, using: &a)
        return (try field.negated(x, using: &a), y)
    }
    /// Sphere V is B/(2*pi)*asin(Z/2), on the original canonical latitude branch.
    public func sphereLatitudeSine<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws -> Field.Value {
        try section.relation.admitProof(limits: limits, using: &a); try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        return try field.dividing(z, field.integer(2, using: &a), using: &a)
    }
    public func firstUV<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> OriginalBoundedSphereConeSurfaceUV {
        try uv(isSphere: sphereIsFirst, limits: limits, using: &a)
    }
    public func secondUV<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> OriginalBoundedSphereConeSurfaceUV {
        try uv(isSphere: !sphereIsFirst, limits: limits, using: &a)
    }
    private func uv<A: ExactScalarAdmission & ~Copyable>(isSphere: Bool, limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> OriginalBoundedSphereConeSurfaceUV {
        try section.relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        let period = try field.importing(section.relation.source.original.labelPeriod, using: &a)
        let u: OriginalBoundedSphereConeSurfaceUV.Coordinate, v: OriginalBoundedSphereConeSurfaceUV.Coordinate
        if isSphere {
            u = .sphereAzimuthLabel(sineArgument: try field.negated(x, using: &a), cosineArgument: y,
                period: period, offset: sphereLabelOffset)
            v = .sphereLatitudeLabel(sine: try field.dividing(z, field.integer(2, using: &a), using: &a), period: period)
        } else {
            u = .coneAngularLabel(halfAngle: coneHalfAngle, period: period, offset: coneLabelOffset)
            v = .authoredScalar(slant)
        }
        try a.retainStorage(bytes: exactScalarPayloadBytes(count: 1, of: OriginalBoundedSphereConeSurfaceUV.self))
        let result = OriginalBoundedSphereConeSurfaceUV(member: self, isSphere: isSphere, u: u, v: v)
        try a.checkpoint(); return result
    }

}
