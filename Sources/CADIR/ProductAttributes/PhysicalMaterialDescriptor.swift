import CADCore

public struct PhysicalMaterialDescriptor: Codable, Hashable, Sendable {
    public let id: PhysicalMaterialID
    public let name: String
    public let description: String
    public let density: PhysicalDensity?
    public init(id: PhysicalMaterialID = PhysicalMaterialID(), name: String, description: String = "", density: PhysicalDensity? = nil) {
        self.id = id; self.name = name; self.description = description; self.density = density
    }
    private enum CodingKeys: String, CodingKey { case id, name, description, density }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .description, .density], in: decoder)
        id = try c.decode(PhysicalMaterialID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        guard c.contains(.density) else { throw ProductAttributeError.invalidSource("Material requires an explicit nullable density field.") }
        density = try c.decodeIfPresent(PhysicalDensity.self, forKey: .density)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description); try c.encode(density, forKey: .density)
    }
}
