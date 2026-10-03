import CADCore

public struct AssemblyDefinition: Codable, Equatable, Sendable {
    public let id: AssemblyDefinitionID
    public var name: String
    /// Distinct standard description owners; nil preserves an unspecified optional value.
    public var productDescription: String?
    public var definitionDescription: String?
    public var features: [FeatureID]
    public var children: [AssemblyOccurrence]
    public init(id: AssemblyDefinitionID = AssemblyDefinitionID(), name: String = "",
                productDescription: String? = nil, definitionDescription: String? = nil,
                features: [FeatureID] = [], children: [AssemblyOccurrence] = []) {
        self.id = id; self.name = name; self.productDescription = productDescription
        self.definitionDescription = definitionDescription; self.features = features; self.children = children
    }
    private enum CodingKeys: String, CodingKey { case id, name, productDescription, definitionDescription, features, children }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try c.validateOnlyExpectedKeys([.id, .name, .productDescription, .definitionDescription, .features, .children], in: decoder)
        id = try c.decode(AssemblyDefinitionID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        productDescription = try c.decode(String?.self, forKey: .productDescription)
        definitionDescription = try c.decode(String?.self, forKey: .definitionDescription)
        features = try c.decode([FeatureID].self, forKey: .features)
        children = try c.decode([AssemblyOccurrence].self, forKey: .children)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(productDescription, forKey: .productDescription)
        try c.encode(definitionDescription, forKey: .definitionDescription)
        try c.encode(features, forKey: .features); try c.encode(children, forKey: .children)
    }
}
