import CADCore

/// One connected selected common curve or point retains the original relation.
public struct OriginalBoundedSphereConeSurfaceComponent: Hashable, Sendable {
    public let relation: OriginalBoundedSphereConeSurfaceRelation
    public var imageDimension: Int { relation.finiteArc?.imageDimension ?? 1 }
    public var fiberDimension: Int { 0 }
    public var isClosed: Bool { relation.finiteArc == nil && relation.finiteCut == nil }
    public var firstSurface: Surface3D { relation.source.original.original.first }
    public var secondSurface: Surface3D { relation.source.original.original.second }
    init(relation: OriginalBoundedSphereConeSurfaceRelation) { self.relation = relation }
    public func member(coneU: OriginalBoundedSphereConeSurfaceRelation.Field.Value,
        branch: Int, coneCycle: OriginalParameterCycle, sphereCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution) throws -> OriginalBoundedSphereConeSurfaceArcMember {
        try relation.member(coneU: coneU, branch: branch, coneCycle: coneCycle, sphereCycle: sphereCycle,
            limits: limits, using: &a)
    }
    public func member(coneU: Double, branch: Int,
        coneCycle: OriginalParameterCycle, sphereCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout OriginalQueryExecution)
        throws -> OriginalBoundedSphereConeSurfaceArcMember {
        try relation.member(coneU: coneU, branch: branch, coneCycle: coneCycle,
            sphereCycle: sphereCycle, limits: limits, using: &a)
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.relation === rhs.relation }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(relation)) }
}
