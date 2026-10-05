import CADCore

/// Actual STEP GROUP declaration, independent of any membership assignment.
public struct IndependentShapeSTEPGroup: Equatable, Sendable {
    public let id: IndependentShapeSTEPGroupID
    public let name: String
    public let description: String?
    public init(id: IndependentShapeSTEPGroupID = .init(), name: String, description: String?) {
        self.id = id; self.name = name; self.description = description
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.id == rhs.id, lhs.name.utf8.elementsEqual(rhs.name.utf8) else { return false }
        switch (lhs.description, rhs.description) {
        case (nil, nil): return true
        case (.some(let a), .some(let b)): return a.utf8.elementsEqual(b.utf8)
        default: return false
        }
    }
    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, description }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try values.validateOnlyExpectedKeys([.id, .name, .description], in: decoder)
        id = try values.decode(IndependentShapeSTEPGroupID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        description = try values.decode(String?.self, forKey: .description)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name)
        try values.encode(description, forKey: .description)
    }
    #endif
}
#if !hasFeature(Embedded)
extension IndependentShapeSTEPGroup: Codable {}
#endif
