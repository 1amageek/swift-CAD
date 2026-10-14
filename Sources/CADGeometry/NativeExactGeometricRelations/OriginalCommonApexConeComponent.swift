/// Retained original common point; its selected parameter fiber may have dimension0..2.
public struct OriginalCommonApexConeComponent: Hashable, Sendable {
    public let relation: OriginalCommonApexConeRelation
    public var imageDimension: Int { 0 }
    public var fiberDimension: Int { relation.fiberDimension ?? 0 }
    init(relation: OriginalCommonApexConeRelation) { self.relation=relation }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.relation === rhs.relation }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(relation)) }
}
