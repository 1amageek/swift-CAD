import CADCore

/// Original ordered or unordered membership with retained actual inverse associations.
public struct IndependentShapeGroup: Equatable, Sendable {
    public let id: IndependentShapeGroupID
    public let name: String
    public let description: String?
    public let family: IndependentShapeGroupFamily
    public let backPointerMembers: [IndependentShapeReference]
    public let originalSTEPGroupID: IndependentShapeSTEPGroupID?
    public let members: [IndependentShapeReference]
    public init(id: IndependentShapeGroupID = .init(), name: String = "", description: String? = nil, members: [IndependentShapeReference], family: IndependentShapeGroupFamily = .unordered, backPointerMembers: [IndependentShapeReference] = [], originalSTEPGroupID: IndependentShapeSTEPGroupID? = nil) {
        self.id = id; self.name = name; self.description = description; self.members = members
        self.originalSTEPGroupID = originalSTEPGroupID; self.family = family; self.backPointerMembers = backPointerMembers
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, description, members, family, backPointerMembers, originalSTEPGroupID }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .description, .members, .family, .backPointerMembers, .originalSTEPGroupID], in: decoder)
        guard c.contains(.description) else { throw DecodingError.keyNotFound(CodingKeys.description, .init(codingPath: c.codingPath, debugDescription: "Required nullable description is absent.")) }
        id = try c.decode(IndependentShapeGroupID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        family = try c.decode(IndependentShapeGroupFamily.self, forKey: .family)
        backPointerMembers = try c.decode([IndependentShapeReference].self, forKey: .backPointerMembers)
        originalSTEPGroupID = try c.decode(IndependentShapeSTEPGroupID?.self, forKey: .originalSTEPGroupID)
        members = try c.decode([IndependentShapeReference].self, forKey: .members)
    }
    #endif
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id, lhs.originalSTEPGroupID == rhs.originalSTEPGroupID, lhs.name.utf8.elementsEqual(rhs.name.utf8), lhs.members == rhs.members, lhs.family == rhs.family, lhs.backPointerMembers == rhs.backPointerMembers else { return false }
        switch (lhs.description, rhs.description) {
        case (nil, nil): return true
        case (.some(let a), .some(let b)): return a.utf8.elementsEqual(b.utf8)
        default: return false
        }
    }

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description); try c.encode(members, forKey: .members)
        try c.encode(family, forKey: .family); try c.encode(backPointerMembers, forKey: .backPointerMembers)
        try c.encode(originalSTEPGroupID, forKey: .originalSTEPGroupID)
    }
    #endif
}

#if !hasFeature(Embedded)
extension IndependentShapeGroup: Codable {}
#endif
