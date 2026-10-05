import CADCore

public struct ProductLayer: Hashable, Sendable {
    public let id: ProductLayerID
    public let name: String
    public let description: String
    public let members: [ProductAttributeTarget]
    public init(id: ProductLayerID = ProductLayerID(), name: String, description: String = "", members: [ProductAttributeTarget]) {
        self.id = id; self.name = name; self.description = description; self.members = members
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey { case id, name, description, members }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .description, .members], in: decoder)
        id = try c.decode(ProductLayerID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description); members = try c.decode([ProductAttributeTarget].self, forKey: .members)
    }
    #endif
}

#if !hasFeature(Embedded)
extension ProductLayer: Codable {}
#endif
