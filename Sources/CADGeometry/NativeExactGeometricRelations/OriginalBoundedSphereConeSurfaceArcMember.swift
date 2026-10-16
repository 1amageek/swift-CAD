import CADCore

/// Checked finite-scope member retains its selected source root, XYZ and UV laws.
public struct OriginalBoundedSphereConeSurfaceArcMember: Sendable {
    public let relation: OriginalBoundedSphereConeSurfaceRelation
    public let position: OriginalBoundedSphereConeSurfaceFiniteArcPosition
    public var branch: Int { position.branch }
    public var coneU: OriginalBoundedSphereConeSurfaceRelation.Field.Value { position.coneU }
    public var proofDepth: ExactScalarDepth { position.proofDepth }
    public var sphereIsFirst: Bool { relation.source.original.sphereIsFirst }
    init(relation: OriginalBoundedSphereConeSurfaceRelation, position: OriginalBoundedSphereConeSurfaceFiniteArcPosition) {
        self.relation = relation; self.position = position
    }
    public func firstUV(limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution)
        throws -> OriginalBoundedSphereConeSurfaceFiniteArcUV {
        try admitProof(limits: limits, using: &a)
        return position.firstUV
    }
    public func secondUV(limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution)
        throws -> OriginalBoundedSphereConeSurfaceFiniteArcUV {
        try admitProof(limits: limits, using: &a)
        return position.secondUV
    }
    public func admitProof(limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws {
        try relation.admitProof(limits: limits, using: &a)
        try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
        try a.checkpoint()
    }
}
