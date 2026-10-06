import CADCore

/// Actual product-definition selection of an original independent representation.
public struct IndependentShapeProductAssociation: Equatable, Comparable, Sendable {
    public let representationID: IndependentShapeRepresentationID
    public let definitionID: AssemblyDefinitionID
    public init(representationID: IndependentShapeRepresentationID, definitionID: AssemblyDefinitionID) {
        self.representationID = representationID; self.definitionID = definitionID
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.representationID == rhs.representationID ? lhs.definitionID < rhs.definitionID : lhs.representationID < rhs.representationID
    }
#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case representationID, definitionID }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.representationID, .definitionID], in: decoder)
        representationID = try c.decode(IndependentShapeRepresentationID.self, forKey: .representationID)
        definitionID = try c.decode(AssemblyDefinitionID.self, forKey: .definitionID)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(representationID, forKey: .representationID); try c.encode(definitionID, forKey: .definitionID)
    }
#endif
}
#if !hasFeature(Embedded)
extension IndependentShapeProductAssociation: Codable {}
#endif
