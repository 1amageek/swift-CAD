import CADCore

/// One exact original geometric image, with complete independent UV fibers.
public struct OriginalCoaxialSurfaceComponent: Hashable, Sendable {
    public let relation: OriginalCoaxialSurfaceSurfaceRelation
    public let branch: Int
    public let interval: Int
    public let imageDimension: Int
    public var fiberDimension: Int { 0 }
    public var phase: ExactParameterInterval<OriginalPhysicalAngleValue> {
        relation.branches[branch].phase.intervals[interval]
    }
    public var firstSurface: Surface3D { relation.source.original.original.first }
    public var secondSurface: Surface3D { relation.source.original.original.second }

    init<A: ExactScalarAdmission & ~Copyable>(relation: OriginalCoaxialSurfaceSurfaceRelation,
        branch: Int, interval: Int, using a: inout A) throws {
        try a.checkpoint()
        guard relation.branches.indices.contains(branch),
            relation.branches[branch].phase.intervals.indices.contains(interval) else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        let selected = relation.branches[branch].phase.intervals[interval]
        guard case .finite(let lower) = selected.lower, case .finite(let upper) = selected.upper else {
            throw OriginalDomainIdentityFailure.invalidDomain
        }
        let order = try relation.source.original.field.compare(lower, upper, using: &a)
        guard order != .greater else { throw OriginalDomainIdentityFailure.invalidDomain }
        self.relation = relation; self.branch = branch; self.interval = interval
        self.imageDimension = order == .equal ? 0 : 1
    }

    public func member<A: ExactScalarAdmission & ~Copyable>(phase: OriginalPhysicalAngleValue,
        coneCycle: OriginalParameterCycle, cylinderCycle: OriginalParameterCycle,
        limits: OriginalDomainIdentityLimits, using a: inout A)
        throws -> (firstUV: [OriginalPhysicalAngleValue], secondUV: [OriginalPhysicalAngleValue], position: OriginalCoaxialSymbolicPosition) {
        try a.checkpoint()
        let field = relation.source.original.field, scope = self.phase
        guard case .finite(let lower) = scope.lower, case .finite(let upper) = scope.upper else {
            throw OriginalDomainIdentityFailure.invalidDomain
        }
        let lowerOrder = try field.compare(phase, lower, using: &a)
        let upperOrder = try field.compare(phase, upper, using: &a)
        guard (lowerOrder == .greater || (lowerOrder == .equal && scope.includesLower)),
            (upperOrder == .less || (upperOrder == .equal && scope.includesUpper)) else {
            throw OriginalDomainIdentityFailure.outsideSupport
        }
        return try relation.member(branch: branch, phase: phase, coneCycle: coneCycle,
            cylinderCycle: cylinderCycle, limits: limits, using: &a)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.relation === rhs.relation && lhs.branch == rhs.branch && lhs.interval == rhs.interval
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(relation)); hasher.combine(branch); hasher.combine(interval)
    }
}
