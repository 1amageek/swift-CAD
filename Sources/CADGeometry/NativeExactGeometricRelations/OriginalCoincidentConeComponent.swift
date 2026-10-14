/// One connected selected image with its retained regular/apex strata.
public struct OriginalCoincidentConeComponent: Hashable, Sendable {
    public let relation: OriginalCoincidentConeRelation
    public let ordinal: Int
    public var piece: OriginalCoincidentConeRelation.Piece { relation.pieces[ordinal] }
    public var imageDimension: Int { piece.imageDimension }
    public var includesApex: Bool { piece.includesApex }
    public var fiberDimension: Int? { includesApex && relation.hasRegular ? nil:includesApex ? relation.apexFiberDimension:0 }
    init(relation:OriginalCoincidentConeRelation,ordinal:Int) { self.relation=relation;self.ordinal=ordinal }
    public static func == (lhs:Self,rhs:Self) -> Bool { lhs.relation === rhs.relation && lhs.ordinal==rhs.ordinal }
    public func hash(into hasher:inout Hasher) { hasher.combine(ObjectIdentifier(relation));hasher.combine(ordinal) }
}
