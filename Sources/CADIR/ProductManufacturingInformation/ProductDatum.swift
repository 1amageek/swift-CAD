import CADCore

public struct ProductDatum: Equatable, Sendable {
    public let id: ProductMetadataID
    public var name: String
    public var description: String
    public var identification: String
    public var target: ProductAttributeTarget
    public init(id: ProductMetadataID = ProductMetadataID(), name: String, description: String = "", identification: String,
                target: ProductAttributeTarget) {
        self.id = id; self.name = name; self.description = description
        self.identification = identification; self.target = target
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, description, identification, target }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .description, .identification, .target], in: decoder)
        id = try c.decode(ProductMetadataID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        identification = try c.decode(String.self, forKey: .identification)
        target = try c.decode(ProductAttributeTarget.self, forKey: .target)
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(identification, forKey: .identification)
        try c.encode(target, forKey: .target)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductDatum: Codable {}
#endif
