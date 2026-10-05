import CADCore

/// Owns one standard PRODUCT, independent of its formation and definition views.
public struct AssemblyProduct: Equatable, Sendable {
    public let id: AssemblyProductID
    public var identifier: String
    public var name: String
    public var description: String?
    public init(id: AssemblyProductID = AssemblyProductID(), identifier: String = "", name: String = "", description: String? = nil) {
        self.id = id; self.identifier = identifier; self.name = name; self.description = description
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && AssemblySourceText(lhs.identifier) == AssemblySourceText(rhs.identifier)
            && AssemblySourceText(lhs.name) == AssemblySourceText(rhs.name)
            && AssemblySourceText.equal(lhs.description, rhs.description)
    }
#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, identifier, name, description }
#endif
#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .identifier, .name, .description], in: decoder)
        id = try c.decode(AssemblyProductID.self, forKey: .id)
        identifier = try c.decode(String.self, forKey: .identifier)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String?.self, forKey: .description)
    }
#endif
#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(identifier, forKey: .identifier)
        try c.encode(name, forKey: .name); try c.encode(description, forKey: .description)
    }
#endif
}

#if !hasFeature(Embedded)
extension AssemblyProduct: Codable {}
#endif
