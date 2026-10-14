import CADCore

/// One of the two disjoint closed common curves with both chart incidents.
public struct OriginalFullConeConeSurfaceComponent: Hashable, Sendable {
    public let branch: Int
    public let relation: OriginalFullConeConeSurfaceRelation
    public var imageDimension: Int { 1 }
    public var fiberDimension: Int { 0 }
    public var isClosed: Bool { true }
    public var firstSurface: Surface3D { relation.source.original.original.first }
    public var secondSurface: Surface3D { relation.source.original.original.second }
    init(relation: OriginalFullConeConeSurfaceRelation, branch: Int) { self.relation = relation; self.branch = branch }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.relation === rhs.relation && lhs.branch == rhs.branch }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(relation)); hasher.combine(branch) }
}
