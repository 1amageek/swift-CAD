import CADCore

/// A named SET of curve/surface selections, separate from GROUP assignment semantics.
public struct IndependentShapeGeometricSet: Equatable, Sendable {
    public let id: IndependentShapeSetID
    public let family: IndependentShapeGeometricSetFamily
    public let name: String
    public let members: [IndependentShapeItemID]
    public init(id: IndependentShapeSetID = .init(), name: String = "", family: IndependentShapeGeometricSetFamily = .geometric, members: [IndependentShapeItemID]) {
        self.id = id; self.family = family; self.name = name; self.members = members
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, family, members }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .family, .members], in: decoder)
        id = try c.decode(IndependentShapeSetID.self, forKey: .id)
        family = try c.decode(IndependentShapeGeometricSetFamily.self, forKey: .family)
        name = try c.decode(String.self, forKey: .name)
        members = try c.decode([IndependentShapeItemID].self, forKey: .members)
    }
    #endif
    public static func == (a: Self, b: Self) -> Bool {
        a.id == b.id && a.family == b.family && a.name.utf8.elementsEqual(b.name.utf8) && a.members == b.members
    }
}

#if !hasFeature(Embedded)
extension IndependentShapeGeometricSet: Codable {}
#endif
