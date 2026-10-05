import CADCore

/// A real representation's membership, not a group assignment or duplicated geometry.
public struct IndependentShapeRepresentation: Equatable, Sendable {
    public let id: IndependentShapeRepresentationID
    public let family: IndependentShapeRepresentationFamily
    public let name: String
    public let contextID: IndependentShapeContextID
    public let members: [IndependentShapeReference]
    public init(id: IndependentShapeRepresentationID = .init(), name: String = "", contextID: IndependentShapeContextID, family: IndependentShapeRepresentationFamily = .shape, members: [IndependentShapeReference]) {
        self.id = id; self.family = family; self.name = name; self.contextID = contextID; self.members = members
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, contextID, family, members }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .contextID, .family, .members], in: decoder)
        id = try c.decode(IndependentShapeRepresentationID.self, forKey: .id)
        family = try c.decode(IndependentShapeRepresentationFamily.self, forKey: .family)
        name = try c.decode(String.self, forKey: .name)
        contextID = try c.decode(IndependentShapeContextID.self, forKey: .contextID)
        members = try c.decode([IndependentShapeReference].self, forKey: .members)
    }
    #endif
    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.family == b.family && a.name.utf8.elementsEqual(b.name.utf8) && a.contextID == b.contextID && a.members == b.members
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeRepresentation: Codable {}
#endif
