import CADCore

/// One connected common curve; both incident root arcs retain the same relation.
public struct OriginalBoundedSphereConeSurfaceComponent: Hashable, Sendable {
    public let relation: OriginalBoundedSphereConeSurfaceRelation
    public var imageDimension: Int { 1 }
    public var fiberDimension: Int { 0 }
    public var isClosed: Bool { true }
    public var firstSurface: Surface3D { relation.source.original.original.first }
    public var secondSurface: Surface3D { relation.source.original.original.second }
    init(relation: OriginalBoundedSphereConeSurfaceRelation) { self.relation = relation }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.relation === rhs.relation }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(relation)) }
}
